# 星枢科学计算族（xisp-sci）

[星枢（xisp）](https://gitcode.com/ystyle/xisp) 的科学计算扩展——NDArray 与建立在它之上的
线性代数 / 统计 / 信号处理。

**当前状态：骨架**。本仓只落结构（独立 workspace、对 `ystyle::xisp` 的依赖接缝、发布配置与
CI 闸门），`xisp_array` 目前只有域声明、没有符号。数组的函数面在
[`docs/plans/`](docs/plans/) 定稿后填入。

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
        ↑    ↑    ↑    ↑
   xisp_io  xisp_linalg  xisp_stats  xisp_signal
        ↑    ↑    ↑    ↑
            xisp_sci           ← 门面：聚合 + 高层 API，不含重实现
```

规则：

1. `array` 是唯一地基，**只有它可以被同族其它模块依赖**；
2. `io` / `linalg` / `stats` / `signal` **互相不得依赖**（各自只依赖 `array` + core）；
3. `sci` 只做聚合 / re-export 与跨域工作流，不重复实现；
4. 全族**不得反向依赖** core 以外的语言本体设施（`repl` / `cli` / `bc`）。

**当前只有 `xisp_array` 一个成员**。其余成员在 `array` 的 API 面定稿后按需加入 —— 它们全部
依赖 `array`，地基没定型时连签名都写不出来，提前占位只是给 lockstep 版本、发布清单和
`check-members.sh` 增加纯维护负担。

## 与 xisp 的版本关系

跨 workspace 依赖**只能走中心仓的精确版本号**（`"ystyle::xisp" = "0.8.0"`），不能用
`{ path = ... }` —— path 依赖发布不了。

由此带来一个必须知道的约束：**xisp 侧加了新 API，本仓要等那个版本发到中心仓才能用上**。
如果发现必须改 xisp 才能实现某个数组能力，多半说明 core 的 `External` 接缝不够用 —— 那是
比"跨仓发版麻烦"重要得多的信号，应当先修接缝。

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

数组相关的设计决策还没全部拍板，详见 xisp 仓
[`docs/plans/2026-10-11-sci-family-design.md` §8](https://gitcode.com/ystyle/xisp/blob/master/docs/plans/2026-10-11-sci-family-design.md)：

| # | 问题 | 现状 |
|---|---|---|
| S2 | 数组的归属：只加 `External`（A）/ 加专用 `Array` 变体（B）/ 完整实现进 core（C） | 待拍板，判据是"JIT 是否为数组特化" |
| S4 | linalg / signal 的性能后端形态 | 建议先纯仓颉，把"同模块内运行时探测"留作后路 |
| S5 | 符号命名策略：命名空间还是前缀 | 待定 |

S1（`External` 接缝）已随 xisp 0.6.0 落地，S3（仓库划分）已按本文档的独立仓方案落地。

## 许可

MIT
