# 计算平台：组成与阶段计划

既然前端先用 Web 顶着、绘图用 Canvas、后续换 ArkUI，那这个平台的架构可以完全围绕 **“引擎与界面解耦”** 来设计。下面是完整的组成拆解和阶段计划。

---

## 一、平台整体组成

```
┌─────────────────────────────────────────────────────────────────────┐
│                        界面层 (可替换)                               │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  Web 前端 (Vue/React + Canvas) → 后续 ArkUI/仓颉鸿蒙          │  │
│  │  - 对话区  - 预览区  - 图表浮层  - 工作空间管理                │  │
│  └───────────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│                        AI 编排层 (atelier)                          │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  意图识别 → 代码生成 → 执行调度 → 结果解释 → 多轮对话          │  │
│  │  - MCP 工具调用  - 上下文管理  - 工作空间状态                   │  │
│  └───────────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│                       计算引擎层 (xisp + 仓颉)                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │ 数组引擎  │ │ 数学函数  │ │ 统计分析  │ │ 插值/拟合 │ │ 线性代数  │  │
│  │ N维数组  │ │ sin/cos  │ │ mean/std │ │ polyfit  │ │ BLAS/    │  │
│  │ 广播/向量化│ │ exp/log  │ │ 分位数   │ │ 样条     │ │ LAPACK   │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │ 信号处理  │ │ 优化     │ │ ODE 求解  │ │ 数据IO   │ │ 符号计算  │  │
│  │ FFT/滤波 │ │ 线性规划  │ │ RK4/     │ │ CSV/     │ │ (后期)   │  │
│  │ 卷积     │ │ 非线性   │ │ 自适应   │ │ Excel/JSON│ │          │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│                       绘图引擎层 (Canvas/HTML)                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────────┐  │
│  │ 2D 绘图  │ │ 3D 绘图  │ │ 图形对象  │ │ 导出 (PNG/SVG/HTML) │  │
│  │ plot     │ │ surf     │ │ handle   │ │                      │  │
│  │ scatter  │ │ mesh     │ │ 图层管理  │ │                      │  │
│  │ bar/hist │ │ plot3    │ │ 交互控制  │ │                      │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│                       数据层 (tsdb + badger-storm)                  │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  工作空间数据  │  会话历史  │  脚本缓存  │  计算结果存储      │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 二、各模块详细说明

### 模块1：数组引擎（最核心）

这是整个平台的**第一性原理**。没有它，其他都是空中楼阁。

```lisp
;; 核心 API
(def a [1 2 3 4 5])              ; 1D
(def b [[1 2] [3 4]])            ; 2D
(def c (zeros 3 4))              ; 初始化
(def d (arange 0 10 0.1))        ; 范围

;; 操作
(shape a)                        ; => [5]
(reshape b [4])                  ; => [1 2 3 4]
(transpose b)                    ; => [[1 3] [2 4]]
(slice a 1 3)                    ; => [2 3]

;; 向量化运算（自动逐元素）
(+ a a)                          ; => [2 4 6 8 10]
(* a 2)                          ; => [2 4 6 8 10]
(sin a)                          ; 逐元素

;; 广播
(+ [[1] [2]] [[3 4]])            ; => [[4 5] [5 6]]

;; 聚合
(sum a) (mean a) (std a)         ; 标量
(sum b :axis 0)                  ; 按列求和
```

**实现要点**：

- 底层用连续的 `f64` 数组存储（列优先，和 BLAS 一致）
- 类型标签：`Int64` / `Float64` / `Complex128` / `Bool`
- 广播规则参考 NumPy
- 切片是视图（零拷贝），不是拷贝

---

### 模块2：数学函数库

```lisp
;; 标量/逐元素
(sin x) (cos x) (tan x) (asin x) (acos x) (atan x)
(exp x) (log x) (log10 x) (sqrt x) (cbrt x)
(abs x) (sign x) (floor x) (ceil x) (round x) (mod x y)
(pow x y) (hypot x y)
(gamma x) (erf x) (erfc x)

;; 复数
(complex 1 2)                    ; => 1+2i
(real z) (imag z) (conj z) (angle z)

;; 常量
pi  e  inf  nan
```

---

### 模块3：统计分析

```lisp
;; 描述统计
(mean a) (median a) (mode a) (std a) (var a)
(min a) (max a) (range a) (quantile a 0.25)
(skewness a) (kurtosis a)
(corr x y) (cov x y)

;; 直方图
(hist a :bins 20)                ; 返回 bin 边界和计数

;; 假设检验
(t-test x y) (chi2-test observed expected)
(anova group1 group2 group3)

;; 回归
(linreg x y)                     ; 最小二乘
(polyfit x y 3)                  ; 多项式拟合
(regress y X)                    ; 多元回归
```

---

### 模块4：线性代数

```lisp
;; 基础
(matmul A B)                     ; 矩阵乘法
(transpose A)
(det A) (trace A) (rank A)
(inv A) (pinv A)                 ; 伪逆

;; 分解
(eig A)                          ; 特征值/向量
(svd A)                          ; 奇异值分解
(qr A) (lu A) (cholesky A)

;; 求解
(solve A b)                      ; Ax=b
(lstsq A b)                      ; 最小二乘
(expm A) (logm A) (sqrtm A)      ; 矩阵函数

;; 稀疏
(sparse I J V)                   ; 从三元组创建
(sparse-zeros M N)
(sparse-eye N)
```

**实现方式**：通过 FFI 绑定 OpenBLAS + LAPACK（参考现有 Lisp 绑定方案）。仓颉已有 FFI 能力，这是纯工程问题。

---

### 模块5：插值、拟合、优化

```lisp
;; 插值
(interp1 x y xi :method :linear)  ; 1D
(interp2 X Y Z Xi Yi)             ; 2D
(spline x y xi)                   ; 样条
(pchip x y xi)                    ; 保形插值

;; 拟合
(polyfit x y 3)
(curvefit model x y :p0 [1 1])

;; 优化
(fmin f x0)                       ; 无约束
(fminbound f a b)                 ; 有界
(fmincon f x0 A b Aeq beq)        ; 约束
(linprog f A b)                   ; 线性规划
(quadprog H f A b)                ; 二次规划

;; 数值积分
(quad f a b)                      ; 自适应
(trapz x y)                       ; 梯形
(simpson x y)

;; ODE
(ode45 f tspan y0)                ; 非刚性
(ode15s f tspan y0)               ; 刚性
```

---

### 模块6：信号处理

```lisp
;; FFT
(fft x) (ifft X)
(fftshift X) (fftfreq n dt)

;; 滤波
(filter b a x)                    ; IIR
(filtfilt b a x)                  ; 零相位
(butter order cutoff)             ; 巴特沃斯

;; 卷积
(conv x y)                        ; 一维
(conv2 A B)                       ; 二维

;; 窗函数
(hann n) (hamming n) (blackman n)

;; 频谱
(spectrogram x :window 256 :overlap 128)
(pwelch x)
```

---

### 模块7：数据 IO

```lisp
;; 文本
(csv-read "data.csv")
(csv-write "out.csv" data)
(json-read "data.json")
(json-write "out.json" data)

;; Excel（后期）
(xls-read "data.xlsx" :sheet 0)
(xls-write "out.xlsx" data)

;; 二进制
(npz-read "data.npz")             ; NumPy 格式
(npz-write "data.npz" :a a :b b)

;; 数据库（你的优势！）
(tsdb-query "SELECT * FROM sensors WHERE time > now() - 1h")
(badger-scan "collection")
```

---

### 模块8：绘图引擎

这是用户感知最强、也是你目前唯一用过的部分。重点设计。

```lisp
;; 2D 基础
(plot x y :title "标题" :xlabel "时间" :ylabel "温度")
(scatter x y :color :red :size 5)
(bar categories values)
(hist data :bins 20)
(errorbar x y :yerr err)
(stem x y)
(stairs x y)
(fill x y :alpha 0.3)

;; 2D 高级
(contour X Y Z :levels 10)
(contourf X Y Z)
(quiver X Y U V)                  ; 向量场
(streamline X Y U V)              ; 流线
(imagesc matrix)
(pcolor X Y C)

;; 3D
(surf X Y Z)
(mesh X Y Z)
(plot3 x y z)
(scatter3 x y z)
(contour3 X Y Z)

;; 图形控制
(figure :size [800 600] :dpi 150)
(subplot 2 2 1)
(hold :on)
(legend "系列1" "系列2")
(colorbar)
(colormap :jet)
(axis :equal :xlim [0 10] :ylim [0 10])
(grid :on)
(title "标题")
(xlabel "X") (ylabel "Y")

;; 导出
(savefig "out.png" :dpi 300)
(savefig "out.svg")
(savefig "out.html")              ; 交互式

;; 交互（Canvas）
(interactive-plot x y)            ; 支持缩放/平移/悬停
```

**实现方案**：

- **方案A（推荐）**：生成 JSON 图形描述，前端用 Canvas 渲染

  ```lisp
  (plot x y)
  ;; => {:type "line" :x [...] :y [...] :title "..." :style {...}}
  ;; 前端接收 JSON，用 Canvas 绘制
  ```

- **方案B**：生成 HTML + Plotly.js，WebView 加载
- **方案C**：生成 SVG（服务端渲染，适合导出）

推荐 A，因为：

1. 前后端解耦，Web 和 ArkUI 都能消费
2. 交互性由前端控制，不依赖 JS 库
3. 导出 PNG 时前端直接 `canvas.toBlob()`

---

### 模块9：工作空间与数据管理

```lisp
;; 工作空间
(workspace-create "实验一")
(workspace-open "实验一")
(workspace-list)
(workspace-save)
(workspace-export "实验一.zip")

;; 数据
(data-load "sales.csv")          ; 加载到工作空间
(data-list)                      ; 列出所有数据集
(data-drop "sales")              ; 删除
(data-preview "sales" :rows 10)

;; 脚本
(script-save "analysis-001.xisp")
(script-run "analysis-001.xisp")
(script-list)
```

底层：每个工作空间 = 一个目录，用 badger-storm 存结构化数据，用 tsdb 存时序数据。

---

### 模块10：AI 编排层（atelier）

```lisp
;; 意图识别
(agent-understand "帮我分析这个CSV")

;; 代码生成
(agent-generate-code 意图 上下文)  ; => xisp 代码

;; 执行
(agent-execute code :sandbox :strict)

;; 结果解释
(agent-explain 执行结果 原始问题)  ; => 自然语言

;; 多轮
(agent-continue "把异常点画出来" :context 上一轮)
```

这个层用 atelier + MCP 实现，xisp 只是执行目标。

---

## 三、阶段计划

### 阶段0：基础设施对齐（与 ERP 并行）

**时间**：在你做 atelier-erp 的阶段完成

| 任务 | 说明 |
| ------ | ------ |
| xisp JIT 稳定性 | BC/JIT 在数值循环场景验证 |
| tsdb/badger-storm API 稳定 | 确保能作为数据层 |
| atelier Agent 能力 | 意图识别、代码生成、结果解释 |
| MCP 工具暴露 | 把 xisp 执行、绘图、数据操作暴露为 MCP 工具 |
| Web 前端框架选型 | Vue/React + Canvas 库选型 |

**交付**：技术栈就绪，可以开始搭建计算平台。

---

### 阶段1：计算核心 MVP（2-3 个月）

**目标**：xisp 能当计算器用，能画图。

| 模块 | 内容 | 优先级 |
| ------ | ------ | -------- |
| 数组引擎 | N 维数组、广播、向量化 | P0 |
| 数学函数 | sin/cos/exp/log/sqrt/abs 等 | P0 |
| 统计 | mean/std/sum/min/max/median | P0 |
| CSV IO | 读写 CSV | P0 |
| 2D 绘图 | plot/scatter/bar/hist（Canvas） | P0 |
| REPL 增强 | 变量显示、help | P1 |

**交付**：

- 用户可以说“读取 sales.csv，画销售额分布直方图”
- 右侧 Canvas 显示图表

**验证**：用真实的 CSV 数据跑通闭环。

---

### 阶段2：AI 工作空间（2-3 个月）

**目标**：对话式界面完整可用。

| 模块 | 内容 | 优先级 |
| ------ | ------ | -------- |
| 对话界面 | 左侧对话、右侧预览 | P0 |
| AI 代码生成 | 自然语言 → xisp | P0 |
| 结果解释 | 执行结果 → 自然语言 | P0 |
| 工作空间管理 | 创建/打开/保存 | P0 |
| 预览区 | 文档/源码/图表切换 | P0 |
| 多轮对话 | 上下文保持 | P1 |
| 图表浮层 | 点击放大 | P1 |

**交付**：

- 用户可以完整地“对话 → 分析 → 看结果 → 追问”
- 生成的 xisp 代码带中文注释

**验证**：让不懂编程的人用一天，看能否完成基本数据分析。

---

### 阶段3：科学计算能力（3-4 个月）

**目标**：从“数据分析”扩展到“科学计算”。

| 模块 | 内容 | 优先级 |
| ------ | ------ | -------- |
| 线性代数 | BLAS/LAPACK FFI | P0 |
| 插值/拟合 | polyfit/interp1/spline | P0 |
| ODE 求解 | ode45/RK4 | P1 |
| 优化 | fmin/linprog | P1 |
| FFT | FFTW FFI | P1 |
| 3D 绘图 | surf/mesh/plot3 | P1 |
| 信号处理 | filter/conv | P2 |

**交付**：

- 用户可以做“拟合这组数据”“解这个微分方程”“做频谱分析”
- 3D 图形可交互旋转

**验证**：找一个工程师用户，用真实工程数据测试。

---

### 阶段4：鸿蒙原生（3-4 个月）

**目标**：从 Web 迁移到 ArkUI/仓颉鸿蒙。

| 模块 | 内容 | 优先级 |
| ------ | ------ | -------- |
| ArkUI 前端 | 用仓颉重写界面 | P0 |
| 原生 Canvas | 替换 Web Canvas | P0 |
| 系统集成 | 文件系统、剪贴板、分享 | P0 |
| 性能优化 | 利用鸿蒙原生能力 | P1 |
| 应用市场发布 | 鸿蒙应用市场 | P0 |

**交付**：鸿蒙 PC 原生应用上架。

---

### 阶段5：生态扩展（持续）

| 模块 | 内容 |
| ------ | ------ |
| 符号计算 | 微分/积分/化简（类似 SymPy） |
| 机器学习 | 基础算法（回归/聚类/分类） |
| 插件系统 | Cordis 插件，用户可扩展 |
| 多人协作 | 工作空间共享 |
| 云端同步 | 可选 |

---

## 四、时间线总览

```
2026 Q3-Q4:  阶段0（与 ERP 并行）
2027 Q1:     阶段1 计算核心 MVP
2027 Q2:     阶段2 AI 工作空间
2027 Q3:     阶段3 科学计算能力
2027 Q4:     阶段4 鸿蒙原生
2028+:       阶段5 生态扩展
```

---

## 五、关键设计原则

1. **引擎与界面解耦**：xisp 引擎输出 JSON，前端消费，换前端不改引擎
2. **绘图用 Canvas，不用原生**：Web 和 ArkUI 都能用 Canvas，降低迁移成本
3. **AI 生成代码要带注释**：让用户“看得懂大概”
4. **分步执行，不一次性生成大段代码**：每步都可验证
5. **数据本地化**：用 tsdb/badger-storm，不上传云端
6. **MCP 优先**：所有能力先暴露为 MCP 工具，AI 通过 MCP 调用

---

## 六、和现有生态的整合点

| 平台模块 | 复用现有 |
| --------- | --------- |
| 数组引擎 | 纯仓颉，新写 |
| 线性代数 | FFI 绑定 BLAS |
| 绘图 | Canvas（前端） |
| 数据层 | tsdb + badger-storm |
| AI 编排 | atelier + MCP |
| 工作空间 | badger-storm |
| 对话管理 | atelier |
| 前端 | cjxt（Web 阶段） |
| 插件 | cordis |

---

## 总结

这个计算平台的组成可以概括为：

> **一个数组引擎 + 一套数学函数 + 一个绘图系统 + 一层 AI 编排 + 一个工作空间**

阶段计划是：

> **先能算（MVP）→ 再能对话（AI 工作空间）→ 再能科学计算（专业能力）→ 再上鸿蒙（原生）**

关键是把 **xisp 引擎** 和 **前端界面** 彻底解耦，这样 Web 阶段和鸿蒙阶段可以平滑切换，不会因为换前端而重写引擎。

需要我细化某个阶段的具体任务清单吗？比如阶段1的数组引擎 API 设计，或者阶段2的 AI 代码生成 prompt 设计？
