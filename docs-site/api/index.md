# API 参考

六个模块，全部符号以 `cangjie::` 前缀。装配后即可在 Lisp 里调用。

## 模块一览

| 模块 | 符号数 | 职责 |
|---|---|---|
| [`xisp_array`](/api/array) | 9 | ndarray：构造、变形、广播、算术 |
| [`xisp_io`](/api/io) | 8 | CSV 读写（含流式） |
| [`xisp_stats`](/api/stats) | 18 | 描述统计、分组、假设检验、图表数据 |
| [`xisp_linalg`](/api/linalg) | 9 | 矩阵乘法、分解、解方程、最小二乘 |
| [`xisp_signal`](/api/signal) | 6 | FFT、卷积、滤波、窗函数 |
| [`xisp_num`](/api/num) | 7 | 插值、拟合、积分、优化、ODE |

**门面 `xisp_sci`** 用 `withSci()` 一次装齐全部。

## 装配

```cangjie
import ystyle::xisp.*
import ystyle::xisp_sci.*

let interp = LispInterpreter([withSci()])
```

精确装配（只装需要的族）：

```cangjie
import ystyle::xisp_array.*
import ystyle::xisp_stats.*

let interp = LispInterpreter([withArray(), withStats()])
```

## 错误约定

所有能力域的错误统一报 `TypeError`，消息里带具体的参数或维度信息：

```lisp
(cangjie::det (cangjie::array [[1 2 3]]))
;; [TypeError] 需要方阵，得到 1×3
```

**奇异、非正定、维度不匹配一律报错**，不返回垃圾值。一个「看起来像答案」的值被下游
继续用，比一次明确的报错危险得多。

## 两套语义的命名约定

| 写法 | 语义 |
|---|---|
| `(max x)` | 数学语义：NaN 传播 |
| `(cangjie::max x)` | 数据分析语义：跳过 NaN |

**加 `cangjie::` 前缀 = 数据分析语义**。裸名是核心提供的数学版本。

这不是重复实现，两套语义各有正确用法。
