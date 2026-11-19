# 统计 stats

`withStats()` 装配。18 个符号。

## 描述统计

| 符号 | 说明 |
|---|---|
| `cangjie::mean` | 算术平均 |
| `cangjie::median` | 中位数 |
| `cangjie::std` | **样本**标准差（除 n−1） |
| `cangjie::std-pop` | 总体标准差（除 n） |
| `cangjie::var` | 样本方差 |
| `cangjie::quantile` | `(quantile x q)` 线性插值（= R 的 type 7） |
| `cangjie::min` | 最小值（跳过 NaN） |
| `cangjie::max` | 最大值（跳过 NaN） |

## 关系

| 符号 | 说明 |
|---|---|
| `cangjie::corr` | 皮尔逊相关系数（成对过滤缺失） |
| `cangjie::cov` | 协方差（样本） |
| `cangjie::corr-matrix` | `(corr-matrix M)` → p×p 相关矩阵 |

## 分组

| 符号 | 说明 |
|---|---|
| `cangjie::group-by` | `(group-by labels values)` → `[[key, ndarray] …]` |
| `cangjie::group-agg` | `(group-agg labels values f)` → `[[key, 结果] …]` |

返回 alist 而不是 HashMap：顺序按类别**首次出现**，报告和图表都依赖顺序稳定。

## 假设检验

| 符号 | 说明 |
|---|---|
| `cangjie::t-test1` | 单样本 → `{t, df, p, mean, se, n}` |
| `cangjie::t-test2` | 双样本 **Welch** → `{t, df, p, mean1, mean2, se, n1, n2}` |
| `cangjie::ci` | `(ci x level)` → `{lo, hi, mean, se, df, tcrit, n}` |

`p` 是双侧 p 值。`ci` 的 `level` 是置信水平（0.95），不是显著性水平。

## 图表数据

| 符号 | 说明 |
|---|---|
| `cangjie::histogram` | `(histogram x bins)` → `{edges, counts}` |
| `cangjie::five-num` | 箱线图五数概括 + 离群点 |

## 空输入约定

所有函数在无有效样本时返回 `NaN`。`std` / `var` 需要至少 2 个样本。

## NaN 处理

除 `min` / `max` 明确跳过 NaN 外，所有函数都跳过 NaN（成对过滤用于 `corr` / `cov`）。
