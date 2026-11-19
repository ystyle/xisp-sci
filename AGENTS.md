# xisp-sci

[星枢（xisp）](https://gitcode.com/ystyle/xisp) 的科学计算扩展——独立 cjpm workspace。

## 本仓特有的三条

1. **依赖 xisp 只能走中心仓版本号**（`"ystyle::xisp" = "x.y.z"`），不用 `{ path = ... }`。
   path 依赖发布不了。要 xisp 加新 API，得先发那个版本。

   > **当前状态（2026-11-19）**：六个成员临时走 `{ path = "../../xisp/core" }`，
   > 这是用户明确授权的开发期例外 —— 数组模块还在迭代，等它稳定再统一改回版本号发版。
   > **发版前必须逐个改回**，`cjpm bundle` 会把 path 原样写进制品，下游拿到就构建失败。
   > 检查：`grep -rn 'path = ' */cjpm.toml`。
2. **族内严格单向依赖**：只有 `xisp_array` 可以被同族其它模块依赖；`io` / `linalg` /
   `stats` / `signal` / `num` 互不依赖；`xisp_sci` 只做聚合。不许反向依赖 `repl` / `cli` / `xisp_bc`。
3. **模块名不能含连字符**：仓库叫 `xisp-sci`，模块必须是 `xisp_array` 这种。

数组的归属（专用 `Array` 变体 vs 纯 `External`）与符号命名策略**还没拍板**，
见 [`docs/plans/2026-11-19-scope-and-roadmap.md`](docs/plans/2026-11-19-scope-and-roadmap.md) §6 ——
动手前先看，别自己定。**范围与阶段路线也在那里，它是本仓的单一来源。**

## 测试

- 白盒测试与被测包同目录（可访问该包 `internal`）；只用 public API 的契约测试放 `xisp_tests/`
- 新功能**必须**写单元测试，先写测试再实现
- 测试暴露的问题要修掉**并补一条用例钉住**

## 质量约定

- **不要考虑时间，不要简化算法，不要简化测试，按最好的来搞**——这是自己的产品
- 不确定就查：仓颉语法查 `cangjie-docs`，历史查忆时塔，当前状态查 milestone
- 提交信息中文，说清「改了什么 + 为什么」

## 常用命令

```shell
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"   # 每个新 shell 都要
cjpm build
cjpm test -j 4 --no-progress
cjpm test --show-all-output --filter 'ArrayDomainTest.*'
cjpm ws check                 # 版本 lockstep
bash scripts/check-members.sh # 成员配置闸门
```

仓颉坑（迭代 `String` 拿到字节、`.trimAscii()`、`match` 的 case 后不能接 `{}`）见工作区
根 `AGENTS.md`。

## 结构

```
.
├── cjpm.toml         # [workspace] 成员清单
├── workspace.toml    # cjpm-ws 产品清单（统一版本 / 发布范围）
├── xisp_array/       # 模块 ystyle::xisp_array —— 数组地基（仓库里唯一的地基）
├── xisp_tests/       # 模块 ystyle::xisp_tests —— 契约 / 集成测试（不发布）
├── docs/             # 范围与路线图（plans/）+ 上游平台愿景（design-platform.md）
└── scripts/          # 闸门脚本
```
