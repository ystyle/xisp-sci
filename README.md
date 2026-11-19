# 星枢科学计算族（xisp-sci）

[星枢（xisp）](https://gitcode.com/ystyle/xisp) 的科学计算扩展——NDArray 与建立在它之上的
线性代数 / 统计 / 信号处理。

**当前状态：数组可算**（阶段 1 + 2 完成）。`xisp_array` 提供 9 个符号：构造
（`array` / `zeros` / `ones` / `arange`）、形状（`shape` / `reshape` / `transpose`）、
视图（`slice`）与谓词（`ndarray?`）。

**算术、归约与数学函数不额外注册符号** —— 它们复用 core 的同名内建，靠能力接口分派：

```lisp
(+ (cangjie::array [1 2 3]) 10)              ; #<ndarray int64 [11 12 13]>
(+ (cangjie::array [[1] [2]]) (cangjie::array [[3 4]]))
                                              ; #<ndarray int64 [[4 5] [5 6]]>  广播
(sum (cangjie::array [1 2 3 4]))              ; 10
(sin (cangjie::array [0.0]))                  ; #<ndarray float64 [0.0]>
(sqrt (cangjie::arange 0 4))                  ; #<ndarray float64 [0.0 1.0 1.4142135623730951 1.7320508075688772]>
```

## 为什么是独立的仓库 / workspace

语言本体（[xisp](https://gitcode.com/ystyle/xisp)）与科学计算族的**发布节奏、外部依赖与目标用户都不同**：

| | 语言本体 `xisp` | 科学计算族 `xisp-sci` |
|---|---|---|
| 外部依赖 | 核心零依赖 | LAPACK / BLAS / FFTW 等 C 库 |
| 发布触发 | 解释器或任一能力域有变 | 数值算法修正 |
| 用户 | 嵌入脚本的宿主 | 做数值计算的人 |

合在一个 workspace 里的代价是 LAPACK 编不过就整族发不出去，语言本体被高风险环节连累。
拆成两个独立仓的代价是版本要对齐（见下节）。设计论证见 xisp 仓的
[`docs/plans/2026-10-11-sci-family-design.md` §4](https://gitcode.com/ystyle/xisp/blob/master/docs/plans/2026-10-11-sci-family-design.md)。

## 族的构成（严格单向依赖）

```
        xisp（core：LispValue / External 协议 / 域装配 / 中断接缝）
              ↑
        xisp_array            ← 唯一地基：dtype / shape / strides / 广播 / 视图
        ↑    ↑    ↑    ↑    ↑
   xisp_io  xisp_linalg  xisp_stats  xisp_signal  xisp_num
        ↑    ↑    ↑    ↑    ↑
                xisp_sci           ← 门面：聚合 + 高层 API，不含重实现
```

规则：

1. `array` 是唯一地基，**只有它可以被同族其它模块依赖**；
2. `io` / `linalg` / `stats` / `signal` / `num` **互相不得依赖**（各自只依赖 `array` + core）；
3. `sci` 只做聚合 / re-export 与跨域工作流，不重复实现；
4. 全族**不得反向依赖** core 以外的语言本体设施（`repl` / `cli` / `bc`）。

`xisp_num`（插值 / 拟合 / 优化 / ODE / 数值积分）不在最初的分族方案里，是补的一个缺口 ——
这些数值方法原先没有归属模块。

**当前只有 `xisp_array` 一个成员**。其余成员在 `array` 的 API 面定稿后按需加入 —— 它们全部
依赖 `array`，地基没定型时连签名都写不出来，提前占位只是给 lockstep 版本、发布清单和
`check-members.sh` 增加纯维护负担。

范围、边界判据、阶段路线图见 [`docs/plans/2026-11-19-scope-and-roadmap.md`](docs/plans/2026-11-19-scope-and-roadmap.md)。

## 与 xisp 的版本关系

**开发期用 path 依赖**，指向同工作区的 xisp 源码：

```toml
[dependencies]
  "ystyle::xisp" = { path = "../../xisp/core" }
  "ystyle::xisp_bc" = { path = "../../xisp/xisp_bc" }   # 仅测试用
```

这样改 xisp 不必每次都发版 —— 否则「数组侧发现 core 缺一个能力 → 改 core → 发整产品 →
等中心仓同步 → 回来继续」这个循环会反复发生，而发版本身就是几分钟到十几分钟的等待。

**发版前必须改回精确版本号**：path 依赖不能 `cjpm bundle` / `publish`。恢复成
`"ystyle::xisp" = "x.y.z"`、跑一遍 `cjpm ws check` 与 `full test` 再发。

这条规则的边界：path 依赖只用于**本仓还没发布过**的开发阶段。一旦本仓有版本在中心仓，
下游拿到的制品里不能有 path 依赖 —— 所以「改回版本号」不是可选项。

另外，如果发现**必须改 xisp 才能实现某个数组能力**，先停一下：那多半说明 core 的
`External` 接缝不够用，比「绕过去」重要得多。

## 模块命名

**模块名不能含连字符**（cjpm 要求合法标识符）。仓库叫 `xisp-sci`，模块必须叫
`xisp_array` / `xisp_linalg` / …，包名 `ystyle::xisp_array`。

## 构建与测试

```shell
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"   # 每个新 shell 都要
cjpm build                    # 编译
cjpm test -j 4 --no-progress  # 跑测试
cjpm ws check                 # 版本 lockstep 闸门
bash scripts/check-members.sh # 成员配置闸门（制品范围 / 元数据 / README）
```

## 发布

准入判据与闸门见工作区 `docs/publish-scope.md`。要点：

- 一个 `[workspace]` 视为一个产品，已发布成员**共用同一版本号**（lockstep），
  任一成员有实质变更即整产品推进一个版本；
- `cjpm publish` 没有 `--registry`，目标仓只能来自 `~/.cjpm/cangjie-repo.toml` ——
  一律走 `./scripts/local-publish.sh` 闸门，不要手敲 `cjpm publish`；
- 发版前必须解包看制品 + 查元数据字段。

## 待决事项

全部列在 [`docs/plans/2026-11-19-scope-and-roadmap.md` §6](docs/plans/2026-11-19-scope-and-roadmap.md)：
默认布局（行优先 / 列优先）、符号命名策略、`linalg` 的 C 后端形态、数组是否要 core 专用变体、
`io` 与 `xisp_json` 的关系。

已经定下来的两条前置：

- **标量数学进 core，不进本仓** —— `(sin 1.0)` 是语言能力，`(sin arr)` 是数组能力，
  同名靠能力接口分派，不搞两套名字；
- **第一版 dtype 只做 `Int64` / `Float64` / `Bool`** —— core 没有复数标量类型，
  加它是 `LispValue` 加变体（~24 处 match），等真有需求再议。

## 许可

MIT
