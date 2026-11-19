# 快速开始

五分钟内跑通第一个数据分析。

## 装配

```cangjie
import ystyle::xisp.*
import ystyle::xisp_sci.*

main() {
    let interp = LispInterpreter([withSci()])
    let r = interp.eval(#"(cangjie::mean (cangjie::array [1 2 3 4 5]))"#)
    println(r)   // 3.000000
}
```

`withSci()` 一次装齐全族六个域。只想用其中一族时可以精确装配：

```cangjie
import ystyle::xisp_array.*
import ystyle::xisp_stats.*

let interp = LispInterpreter([withArray(), withStats()])
```

## 第一个数组

```lisp
(cangjie::array [1 2 3])              ; 一维整数数组
(cangjie::array [[1 2] [3 4]])        ; 二维
(cangjie::arange 0 10 2)              ; [0 2 4 6 8]
(cangjie::zeros 3 4)                  ; 3×4 全零
(cangjie::reshape (cangjie::arange 0 6) [2 3])
```

数组在 Lisp 里是一个**外部值**（`#<ndarray float64 …>`），可以直接参与运算：

```lisp
(+ (cangjie::array [1 2 3]) 10)       ; [11 12 13] —— 标量自动广播
(+ (cangjie::array [1 2 3]) (cangjie::array [10 20 30]))
(> (cangjie::array [1 5 3]) 2)        ; [false true true]
```

## 第一次统计

```lisp
(define x (cangjie::array [2.0 4.0 4.0 4.0 5.0 5.0 7.0 9.0]))

(cangjie::mean x)        ; 5.0
(cangjie::median x)      ; 4.5
(cangjie::std x)         ; 2.13809 —— **样本**标准差（除 n−1）
(cangjie::quantile x 0.25)   ; 4.0
(min x)                  ; 2.0  —— 数学语义，NaN 会传播
(max x)                  ; 9.0
```

`std` 除以 `n−1` 而不是 `n`。这与 NumPy 相反（`np.std` 默认 `ddof=0`）。
需要总体标准差时用 `cangjie::std-pop`。

## 第一次读文件

```lisp
(define d (cangjie::csv-read "data.csv"))

(hashmap-keys d)                        ; 列名列表
(length (hashmap-get d "amount"))       ; 行数
(cangjie::mean (hashmap-get d "amount"))
```

列类型是**自动推断**的：

| 列内容 | 推断结果 |
|---|---|
| 全是整数 | `int64` 数组 |
| 有小数或缺失 | `float64` 数组（缺失是 `NaN`） |
| 其它 | 字符串列表 |

## 下一步

- [数组：一切的基础](/guide/02-arrays) —— 广播、视图、dtype
- [读数据：CSV 与缺失值](/guide/03-data-io) —— 流式读大文件、10 种缺失标记
- [Iris：十分钟入门](/cookbook/iris) —— 完整走一遍真实数据
