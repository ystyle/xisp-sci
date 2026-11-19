# 数组：一切的基础

`xisp_array` 提供 ndarray，它是本套件所有计算的数据载体。

## 为什么数组是外部值

`xisp` 核心的 `LispValue` 是个**封闭枚举**，没有 `Array` 变体。加一个变体等于动核心的
判别式，所有 `match` 都要改。所以数组走 `LispExternal` 通道：核心提供一组能力接口
（可索引、可比较、可算术、可归约、可逐元素），外部值自己实现，核心不需要知道
「数组」这个东西存在。

这个通道对任何类型开放：稀疏矩阵、DataFrame、图，都能用同一套接口接进来。

## 构造

```lisp
(cangjie::array [1 2 3])                  ; 从字面量
(cangjie::array [[1 2] [3 4]])            ; 嵌套 = 二维
(cangjie::zeros 3 4)                      ; 3×4 全零（float64）
(cangjie::ones 2 3)                       ; 2×3 全一
(cangjie::arange 0 10)                    ; [0 1 … 9]
(cangjie::arange 0 10 3)                  ; [0 3 6 9]
(cangjie::arange 0.0 1.0 0.25)            ; [0.0 0.25 0.5 0.75]
```

注意 `[...]` 字面量本身仍然是**列表**，不是数组。要变数组必须显式 `cangjie::array`。
这是有意的。列表和数组的语义不同（列表可嵌套任意结构，数组要求矩形），
让字面量自动推断成其中一个，总有一类用法会写出意外的结果。

## dtype

只有三种：`int64`、`float64`、`bool`。

从字面量推断：全整数 → `int64`；有一个小数 → `float64`；全是 `#t`/`#f` → `bool`。
混合整数与布尔会提升为 `int64`。

**没有 complex**。需要复数的地方用 `{"re": …, "im": …}` 两个数组表示（见 `xisp_signal`）。

## 形状与索引

```lisp
(define a (cangjie::array [[1 2 3] [4 5 6]]))

(cangjie::shape a)      ; [2 3]
(length a)              ; 6 —— **元素总数**，不是某一维
(nth a 0)               ; 1 —— 按行优先的**扁平**下标
```

`length` 是元素总数、`nth` 是扁平下标，这两个约定是刻意与「一维数组」保持一致的：
把它们定义成「第一维长度」「按维度索引」的话，同一个函数在不同维数下行为就变了。

## 变形

```lisp
(cangjie::reshape a [3 2])        ; 2×3 → 3×2
(cangjie::reshape a [-1 2])       ; -1 表示自动推断
(cangjie::transpose a)            ; 转置
(cangjie::slice a 1)              ; 沿第 0 维取第 1 行
```

`reshape` **不复制数据**，只改 strides。数据仍在一块连续内存里。

## 广播

NumPy 风格。两个数组形状不同时，长度 1 的维度会被「拉伸」：

```lisp
(+ (cangjie::array [[1 2 3]]) (cangjie::array [[10] [20]]))
;; [[11 12 13]
;;  [21 22 23]]
```

规则：从**末维**往前对齐，每一维要么相等、要么其中一个是 1。否则报错，不会静默截断。

实现上是把被广播那一维的 stride 设成 0，所以广播不复制数据，只是同一个元素被
反复读到。这也是为什么 `(+ a 1)` 在 100 万元素的数组上是瞬间完成的。

## 运算

```lisp
(+ a b)  (- a b)  (* a b)  (/ a b)      ; 逐元素；/ 结果恒为 float64
(< a b)  (> a b)  (= a b)               ; 逐元素比较 → bool 数组
(- a)                                   ; 一元取负
```

整数除法与浮点除法是**两个操作**，不会自动提升：

```lisp
(/ (cangjie::array [1 2 3]) 2)          ; [0.5 1.0 1.5] —— 恒 float64
```

## 归约

```lisp
(+ a b c)              ; 多参数时退化为逐元素相加
(sum a)                ; 求和
(product a)            ; 连乘
(max a)  (min a)       ; 最大/最小
```

⚠️ `max` / `min` 是**数学语义**：数组里有一个 `NaN` 就整体返回 `NaN`。
数据分析场景（`NaN` 表示缺失）请用 `cangjie::max` / `cangjie::min`，它们跳过 `NaN`。

## 逐元素数学

```lisp
(sin a) (cos a) (exp a) (log a) (sqrt a) (abs a) (floor a) (ceil a)
```

这些是核心内建，不是 sci 模块提供的，因为它们的语义是「对标量函数逐元素应用」，
属于数组能力本身。数组只要实现 `LispExternalElementwise`，就自动获得全部标量数学函数。

## 显示

```lisp
(cangjie::array [1.5 2.5])
;; #<ndarray float64 [1.5 2.5]>

(cangjie::zeros 100 100)
;; #<ndarray float64 100×100（超过 20 个元素，省略显示）>
```

大数组截断显示，不打印全部。一个 100 万元素的数组打到终端上是灾难。
