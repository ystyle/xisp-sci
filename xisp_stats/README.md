# xisp_stats

星枢科学计算统计：描述统计、分位数、相关与直方图。

```lisp
(define d (cangjie::csv-read "sales.csv"))
(cangjie::mean (hashmap-get d "amount"))     ; 均值
(cangjie::std (hashmap-get d "amount"))      ; 样本标准差
(cangjie::median (hashmap-get d "region"))   ; 中位数
(cangjie::corr (hashmap-get d "amount") (hashmap-get d "qty"))
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

同时接受 ndarray 与普通列表：`(cangjie::mean arr)` 与 `(cangjie::mean [1 2 3])` 都能用。

## 设计要点

**缺失值跳过**。所有函数忽略 `NaN`（CSV 里的空单元格）。这是唯一不会把"缺失"和
"真的是 0"混为一谈的做法：`[1, NaN, 3]` 的均值是 2 而不是 1.333。

**`corr` / `cov` 成对过滤**。任一侧缺失就丢整个样本。若各自独立跳 `NaN`，两个数组会
错位 —— 算的是"1 号的价格对 5 号的销量"，数字看着正常，结论完全错。

**空输入返回 `NaN`** 而不是报错。"没有数据的均值"是未定义的，返回 0 会让调用方拿着一个
看起来正常的结果继续算下去；`NaN` 会一路传播，在最终结果处暴露。

**`std` 默认用样本自由度（`n-1`）**，注意这与 NumPy 相反（`np.std` 默认 `ddof=0`）。
提供 `std-pop` 给需要总体标准差的场景。选样本作默认是因为数据分析里手上的数据几乎总是样本。

## 许可

MIT
