# 成员与发布

## 九个成员

| 成员 | 类型 | 说明 |
|---|---|---|
| `xisp_array` | 库 | ndarray |
| `xisp_io` | 库 | CSV 读写 |
| `xisp_stats` | 库 | 统计与推断 |
| `xisp_linalg` | 库 | 线性代数 |
| `xisp_signal` | 库 | 信号处理 |
| `xisp_num` | 库 | 数值方法 |
| `xisp_sci` | 库 | 门面：聚合全部 |
| `xisp_tests` | 测试 | 契约测试，不发布 |
| `bench` | 可执行 | 基准测试，不发布 |

## 依赖方向

```
        xisp (核心)
            ↑
  ┌──┬──┬──┼──┬──┐
array io stats linalg signal num      ← 六族互不依赖
  └──┴──┴──┼──┴──┘
            ↑
        xisp_sci (门面)
```

六族**严格单向**：都只依赖 `xisp` 核心，互不依赖。这样「只想用统计」的宿主
可以只装 `xisp_stats`。

门面是唯一允许「知道所有族」的地方，只做聚合、不含重实现。

## 开发期依赖用 path

```toml
[dependencies]
  "ystyle::xisp" = { path = "../../xisp/core" }
```

好处是改 `xisp` 核心立即生效，不用每次都发版等中心仓同步。

⚠️ **发版前必须改回版本号**。`cjpm bundle` 会把 path 依赖原样写进制品，下游拿到
就构建失败。

## 两道闸门

```shell
cjpm ws check              # 版本一致、依赖一致、无环
bash scripts/check-members.sh   # README、制品清单、原生依赖白名单
```

`check-members.sh` 读 `workspace.toml` 的 `[workspace.publish] exclude` 作为发布范围的
单一来源，脚本不另立判据。

## 版本

全部已发布成员共用**同一个版本号**（lockstep）。任一成员有实质变更即整产品推进一个版本。

当前 `0.2.0`（未发版，等能力稳定后统一发 `0.3.0`）。

## 编译选项

**每个成员的 `cjpm.toml` 都必须写**：

```toml
compile-option = "-O2 -Woff unused"
```

workspace 根的 `compile-option` 不会向下传递，必须逐个成员写。
原因见[性能](/reference/performance#必须开-o2)。
