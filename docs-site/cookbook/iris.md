# Iris：十分钟入门

用最经典的分类数据集走一遍完整链路。

数据在仓库的 `bench/data/iris.csv`（150 行 × 5 列）。

## 1. 读进来，看结构

```lisp
(define d (cangjie::csv-read "iris.csv"))

(hashmap-keys d)
;; ("sepal_length" "sepal_width" "petal_length" "petal_width" "species")
```

前四列被推断成 `float64` 数组，`species` 被推断成字符串列表，因为它装的是标签。

## 2. 描述统计

```lisp
(cangjie::mean (hashmap-get d "sepal_length"))     ; 5.8433
(cangjie::std  (hashmap-get d "sepal_length"))     ; 0.8280
(cangjie::median (hashmap-get d "sepal_length"))   ; 5.8
```

这三个数字与这个数据集的公开统计量完全一致（5.843333 / 0.828066）。
这不是巧合：它们是整条链路（CSV 解析 → 类型推断 → ndarray → 累加）的验收。

## 3. 分组：这才是重点

整体均值 5.84 掩盖了一件重要的事：三个物种的大小差得很远。

```lisp
(define g (cangjie::group-agg (hashmap-get d "species")
                              (hashmap-get d "petal_length")
                              cangjie::mean))
;; (("setosa" 1.464) ("versicolor" 4.260) ("virginica" 5.552))
```

**这组数字是整份文档里最重要的一行**。整体看花瓣长度均值 3.76，
但真实情况是「1.5 / 4.3 / 5.6 三群」，中间没有过渡。

任何在整体上做的判断（比如「花瓣长度大约 3.76」）都在描述一个不存在的「平均鸢尾花」。

## 4. 画图要什么数据

箱线图：三个物种各自的五数概括。

```lisp
(cangjie::five-num (cadr (car g)))
```

| 物种 | Q1 | 中位数 | Q3 | 须 | 离群点 |
|---|---|---|---|---|---|
| setosa | 1.4 | 1.5 | 1.575 | [1.2, 1.7] | 4 |
| versicolor | 4.0 | 4.35 | 4.6 | [3.3, 5.1] | 1 |
| virginica | 5.1 | 5.55 | 5.875 | [4.5, 6.9] | 0 |

注意 **须不是最小/最大值**：Tukey 的 1.5·IQR 规则下，须止于围栏内最远的实际数据点。
setosa 有 4 个离群点，它们的值在 1.0~1.1 和 1.9 附近。

如果用极值当须，这 4 个点会把箱体压扁到看不出中位数在哪。

## 5. 变量之间的关系

```lisp
(cangjie::corr (hashmap-get d "petal_length") (hashmap-get d "petal_width"))
;; 0.9628 —— 极强正相关
```

花瓣越长越宽，这符合直觉。但别忘了第 3 步的教训：这个 0.96 是三群叠加出来的。
在单个物种内部，相关性会弱得多。这是辛普森悖论的典型场景。

## 6. 物种之间差异显著吗

```lisp
(define gg (cangjie::group-by (hashmap-get d "species")
                              (hashmap-get d "petal_length")))
(cangjie::t-test2 (cadr (car gg)) (cadr (cadr gg)))    ; setosa vs versicolor
```

p 值会小到浮点数下溢。1.5 和 4.3 两组之间没有任何重叠，这种差异不可能来自偶然。

## 完整代码

```lisp
(define d (cangjie::csv-read "iris.csv"))
(define species (hashmap-get d "species"))
(define pl (hashmap-get d "petal_length"))

(println "整体均值：" (cangjie::mean pl))
(println "分组均值：" (cangjie::group-agg species pl cangjie::mean))
(println "箱线图："   (map (lambda (kv) (cangjie::five-num (cadr kv)))
                          (cangjie::group-by species pl)))
```

## 从这份数据能学到什么

1. **先分组再看统计量**。整体均值可能描述一个不存在的东西。
2. **须不是极值**。箱线图用围栏，是为了不被离群点压扁。
3. **强相关可能来自分组**。三群叠加会造出群内不存在的相关性。
