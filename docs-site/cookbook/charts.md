# 图表数据：交给前端渲染

本套件**不画图**。它只产出可渲染的结构，渲染交给前端。

## 为什么不做渲染

引入图形依赖会让「一个数据分析库」变成「半个绘图库」：字体、坐标轴、颜色、
交互、导出格式……每一项都是独立的复杂度，而且和数据分析本身没有关系。

更重要的是：**图表是给谁看的，决定了它该长什么样**。终端里用 ASCII 画、网页里用
Canvas 画、报告里用 PDF 画，同一个数据集需要三种完全不同的呈现。把这些塞进核心库，
等于替调用方做了他们最清楚的决定。

## 散点图、折线图：不需要专门函数

要的就是数据本身。

```lisp
(define x (hashmap-get d "weight"))
(define y (hashmap-get d "mpg"))
;; 两个 ndarray 直接交给前端
```

不需要一个「散点图函数」把它们包起来，那只会增加一层没有信息量的抽象。

## 直方图

```lisp
(cangjie::histogram x 10)
;; → {"edges": #<ndarray float64 [0.0 2.5 5.0 …]>,
;;    "counts": #<ndarray int64 [11 30 24 …]>}
```

`edges` 有 `bins+1` 个元素，`counts` 有 `bins` 个。直接对应柱状图的 x 轴边界与柱高。

## 箱线图

```lisp
(cangjie::five-num x)
;; → {"min": 1.0, "q1": 3.25, "median": 5.5, "q3": 7.75, "max": 100.0,
;;    "iqr": 4.5, "lower_fence": -3.5, "upper_fence": 14.5,
;;    "low_whisker": 1.0, "high_whisker": 9.0,
;;    "outliers": #<ndarray float64 [100.0]>, "n": 10}
```

### 须不是最小/最大值

这是箱线图最容易被画错的地方。Tukey 的 1.5·IQR 规则：

```
IQR   = Q3 − Q1
下围栏 = Q1 − 1.5·IQR
上围栏 = Q3 + 1.5·IQR
```

**须止于围栏内最远的实际数据点**，围栏外的点单独画成散点。

上面例子里数据是 `[1..9, 100]`：上围栏 14.5，所以 100 是离群点，
而须停在 9，不是 100。

如果用极值当须，一个离群点就会把整个箱体压成一条线，中位数在哪完全看不出来。

## 相关矩阵

```lisp
(cangjie::corr-matrix M)      ; M 是 n×p，输出 p×p
```

对角线恒为 1，矩阵对称。直接对应热力图。

按**成对删除**处理缺失：某行在变量 i 上缺失、在 j 上没有时，这一行对 `(i,j)`
不可用，但对其它变量对仍然可用。

## 一个完整的例子

```lisp
(define d (cangjie::csv-read "iris.csv"))
(define species (hashmap-get d "species"))
(define pl (hashmap-get d "petal_length"))

;; 各物种的箱线图数据
(map (lambda (kv) (list (car kv) (cangjie::five-num (cadr kv))))
     (cangjie::group-by species pl))

;; 各物种的直方图数据
(map (lambda (kv) (list (car kv) (cangjie::histogram (cadr kv) 8)))
     (cangjie::group-by species pl))
```

输出是一份纯数据的 alist，前端可以：
- 用 D3 / ECharts / Chart.js 画
- 序列化成 JSON 传给浏览器
- 转成 matplotlib / gnuplot 的数据文件
- 在终端里用 ASCII 画

**渲染方式与数据分析完全解耦**，这是这个设计的全部意义。
