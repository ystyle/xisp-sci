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
| `cangjie::min` | 最小值（**跳过 NaN**） |
| `cangjie::max` | 最大值（**跳过 NaN**） |
| `cangjie::group-by` | 按类别分组 → `[[key, ndarray] …]` |
| `cangjie::group-agg` | 分组后聚合 → `[[key, 聚合值] …]` |

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
