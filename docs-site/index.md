---
layout: home

hero:
  name: 星枢科学计算
  text: 在 Lisp 里做数据分析
  tagline: 建在星枢 Xisp 之上的科学计算套件 —— 数组、IO、统计、线代、信号、数值方法
  actions:
    - theme: brand
      text: 五分钟上手
      link: /guide/01-quickstart
    - theme: alt
      text: Iris 实战
      link: /cookbook/iris
    - theme: alt
      text: API 参考
      link: /api/

features:
  - icon: 📊
    title: 从 CSV 到结论
    details: 读真实数据、推断列类型、跳过缺失值、算统计量 —— 一条链路走通，不用在三种工具之间倒数据。
  - icon: 🧮
    title: 数组是一等公民
    details: ndarray 带 dtype、shape、broadcast。纯仓颉实现，零外部依赖，不装 BLAS 也能算 1000×1000 的乘法。
  - icon: 📈
    title: 统计不止均值
    details: 分位数、相关系数、分组聚合、t 检验、置信区间、箱线图五数概括 —— 以及「样本标准差还是总体标准差」这类会被搞错的地方。
  - icon: 🎯
    title: 算对了才算完
    details: 统计量与 pandas 逐位比对；回归系数与 Python 的正规方程对照（不同算法给同一个答案才算证据）；t 分布拿教科书分位数表钉住。
  - icon: 🔬
    title: 六族能力
    details: array / io / stats / linalg / signal / num，严格单向依赖，谁也不知道其它族存在。只想用统计就不必把 FFT 拖进来。
  - icon: ⚡
    title: 性能有数
    details: matmul 1000×1000 约 1 秒 / 2 GFLOPS；-O2 开关差 8~68 倍（实测，不是估计）。
---

## 三十秒看一眼

```lisp
(define d (cangjie::csv-read "sales.csv"))          ; 读数据，自动推断列类型
(cangjie::mean (hashmap-get d "amount"))            ; 125.0
(cangjie::std  (hashmap-get d "amount"))            ; 样本标准差
(cangjie::corr (hashmap-get d "amount") (hashmap-get d "qty"))
(cangjie::group-agg (hashmap-get d "region") (hashmap-get d "amount") cangjie::mean)
```

## 它不是什么

- **不是绘图库**。图表数据（直方图、箱线图五数、相关矩阵）由本套件产出，渲染交给前端。
- **不是机器学习框架**。这里没有梯度下降、没有神经网络，只有统计学与线性代数。
- **不是 R 或 pandas 的替代品**。它是「你的 Cangjie 程序需要一个嵌入式脚本层，而这个脚本层要能算点东西」时的答案。

## 装什么

```toml
[dependencies]
  "ystyle::xisp_sci" = "0.3.0"     # 门面：一次装齐全族
```

⚠️ **你的工程必须开 `-O2`**。实测同一份 `matmul`，加与不加差 **8~68 倍** ——
1000×1000 从 0.97 秒变成 29 秒。这不是建议，是硬性要求。详见[性能与基准](/reference/performance)。
