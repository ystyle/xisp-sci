# xisp_array

星枢（[xisp](https://gitcode.com/ystyle/xisp)）科学计算族的**唯一地基**：NDArray 的
dtype / shape / strides / 广播 / 视图 / 基础归约。

同族其它模块（`io` / `linalg` / `stats` / `signal` / `sci`）都建立在它之上，
所以它的 API 一旦发布就要保持兼容。

## 当前状态

**骨架**：只有域声明（`arrayDomain()` / `withArray()`），符号清单为空。
函数面在 [`../docs/plans/`](../docs/plans/) 定稿后填入。

```cangjie
import ystyle::xisp.*
import ystyle::xisp_array.*

let interp = LispInterpreter([withArray()])
```

## 设计定位

数组**不**做成 core 的一等变体也能获得近乎一等的观感——`length` / `nth` / `print` / `=` /
`type-of` 会探测能力接口（`LispExternalIndexable` / `Equatable` / …），走 `External` 接入即可。
专用变体唯一不可替代的收益是**编译器特化**。

完整论证见 xisp 仓
[`docs/plans/2026-10-11-sci-family-design.md` §7](https://gitcode.com/ystyle/xisp/blob/master/docs/plans/2026-10-11-sci-family-design.md)。

## 许可

MIT
