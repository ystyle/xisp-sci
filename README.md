# 星枢科学计算 · xisp-sci

建在 [星枢 Xisp](https://gitcode.com/ystyle/xisp) 之上的科学计算套件：在 Lisp 里读数据、算统计、拟合回归。

读 CSV、解方程、做 FFT 都在同一个嵌入式脚本层里完成。纯仓颉实现，零外部依赖。

```
Cangjie 1.0+  ·  MIT  ·  0.2.0（开发中，未发布）
```

---

## 特性

**📊 从 CSV 到结论，一条链路**
自动推断列类型、识别 10 种缺失标记、跳过 NaN 算统计。不用在三种工具之间倒数据。

**🧮 ndarray 是一等公民**
dtype、shape、strides、广播、视图。`(+ a 1)` 在 100 万元素上瞬间完成，因为广播不复制数据。

**📈 统计不止均值**
分位数、相关系数、分组聚合、t 检验、置信区间、箱线图五数概括。以及「样本标准差还是总体标准差」这类会被搞错的地方。

**🎯 算对了才算完**
统计量与 pandas 逐位比对；回归系数与 Python 的正规方程对照，不同算法给同一个答案才算证据；t 分布拿教科书分位数表钉住。

**🔬 六族解耦**
`array` / `io` / `stats` / `linalg` / `signal` / `num` 严格单向依赖。只想用统计，就不必把 FFT 和线代拖进来。

**⚡ 性能有数**
`matmul` 1000×1000 约 1 秒，2 GFLOPS。`-O2` 开关差 8~68 倍，这个数字来自实测。

---

## 三十秒看一眼

```lisp
;; 读真实数据
(define d (cangjie::csv-read "iris.csv"))

;; 描述统计
(cangjie::mean (hashmap-get d "petal_length"))     ; 3.7587
(cangjie::std  (hashmap-get d "petal_length"))     ; 1.7644（样本标准差）

;; 分组 —— 这里才是重点
(cangjie::group-agg (hashmap-get d "species")
                    (hashmap-get d "petal_length")
                    cangjie::mean)
;; (("setosa" 1.464) ("versicolor" 4.260) ("virginica" 5.552))
```

整体均值 3.76 描述的是一个不存在的平均鸢尾花。真实情况是 1.5 / 4.3 / 5.6 三群，中间没有过渡。

```lisp
;; 回归：两次期中成绩能预测期末吗
(cangjie::lstsq X y)        ; → [-1.83 0.153 0.987]
;; R² = 0.82，RMSE = 1.93 分

;; 男女差异显著吗
(cangjie::t-test2 female male)
;; → p = 0.0396 —— 显著，但只差 0.95 分，比模型误差还小
```

---

## 用法

```toml
[dependencies]
  "ystyle::xisp_sci" = "0.3.0"     # 门面：一次装齐全族
```

```cangjie
import ystyle::xisp.*
import ystyle::xisp_sci.*

let interp = LispInterpreter([withSci()])
println(interp.eval(#"(cangjie::mean (cangjie::array [1 2 3]))"#))
```

只想要一族时精确装配：

```cangjie
LispInterpreter([withArray(), withStats()])
```

> ⚠️ **你的工程必须开 `-O2`**
> ```toml
> [package]
>   compile-option = "-O2"
> ```
> 实测同一份 `matmul`，加与不加差 8~68 倍：1000×1000 从 0.97 秒变成 29 秒。
> 发布的是源码包，不加优化就得不到这个性能，**而且不会有任何警告**。

---

## 文档

**📖 [完整文档站](https://ystyle.top/xisp-sci/)**

| | |
|---|---|
| [快速开始](https://ystyle.top/xisp-sci/guide/01-quickstart) | 五分钟跑通第一个分析 |
| [Iris 实战](https://ystyle.top/xisp-sci/cookbook/iris) | 十分钟走完真实数据 |
| [教师工作流](https://ystyle.top/xisp-sci/cookbook/teacher) | 一个不懂编程的人怎么用 |
| [API 参考](https://ystyle.top/xisp-sci/api/) | 六个模块 75 个符号 |
| [设计取舍](https://ystyle.top/xisp-sci/reference/design) | 为什么这样设计、放弃了什么 |
| [性能与基准](https://ystyle.top/xisp-sci/reference/performance) | 全部实测数字 |

---

## 六个模块

| 模块 | 符号 | 职责 |
|---|---|---|
| `xisp_array` | 9 | ndarray：构造、变形、广播、算术 |
| `xisp_io` | 8 | CSV 读写（含 64KB 流式，内存与文件大小无关） |
| `xisp_stats` | 18 | 描述统计、分组、假设检验、图表数据 |
| `xisp_linalg` | 9 | 矩阵乘法、LU/QR/Cholesky、解方程、最小二乘 |
| `xisp_signal` | 6 | FFT（任意长度）、卷积、IIR 滤波、窗函数 |
| `xisp_num` | 7 | 插值、多项式拟合、积分、优化、ODE |

加上门面 `xisp_sci`，共 7 个可发布成员 + 2 个开发成员（契约测试、基准）。

---

## 几条设计原则

**数组是外部值，不是核心类型。** 核心的 `LispValue` 是封闭枚举，加变体要动所有 `match`。所以走能力接口通道，这套通道对稀疏矩阵、DataFrame 等任何类型同样开放。

**两套 NaN 语义并存。** `(max x)` 是数学语义（NaN 传播），`(cangjie::max x)` 是数据分析语义（跳过缺失）。**加前缀 = 数据分析**，这是全套件的命名约定。

**不做绘图。** 只产出可渲染的结构（直方图边界与计数、箱线图五数、相关矩阵），渲染交给前端。图表给谁看决定了它该长什么样，这个决定应该由调用方做。

**不接 BLAS / LAPACK。** `cjpm` 没有可选依赖，接 C 库意味着每个宿主都得装 C 工具链。代价是慢 25~50 倍，对 n < 1000 的数据分析够用。

---

## 构建

```shell
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"
cjpm build -j 8
cjpm test -j 4 --no-progress
```

基准（七项，含 -O2 A/B 与真实 Matrix Market 稀疏矩阵）：

```shell
cd bench && ./target/release/bin/ystyle::bench    # 报告写到 bench/report.md
```

## 许可

MIT
