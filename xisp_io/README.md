# xisp_io

星枢科学计算数据 IO：**CSV 读写**与列类型推断。

## 两种用法

| 场景 | 用法 | 内存 |
|---|---|---|
| 小文件、要按列做统计 | `(cangjie::csv-read path)` → `HashMap<列名, 列值>` | 全量 |
| 大文件、逐行流式处理 | `(cangjie::csv-open path)` + `csv-next` / `csv-each` + `csv-close` | **与文件大小无关** |

```lisp
;; 一次性
(define d (cangjie::csv-read "sales.csv"))
(cangjie::mean (hashmap-get d "amount"))

;; 流式
(define cur (cangjie::csv-open "big.csv"))
(cangjie::csv-next cur)                        ; 表头行
(cangjie::csv-each cur (lambda (row) (println (nth row 0))))
(cangjie::csv-close cur)
```

## 符号

| 符号 | 说明 |
|---|---|
| `cangjie::csv-read` | 读文件（首行是表头），可选第二参数限制行数 |
| `cangjie::csv-parse` | 从字符串解析 |
| `cangjie::csv-open` | 打开流式游标 |
| `cangjie::csv-next` | 取下一行（`Str` 列表）；EOF 返回 `nil` |
| `cangjie::csv-each` | 对剩余每行调用处理函数，返回行数 |
| `cangjie::csv-close` | 关闭游标（**必须**，否则文件句柄要等 GC） |
| `cangjie::csv-write` | 写出（路径 + HashMap + 可选列序） |
| `cangjie::csv-format` | 生成 CSV 文本 |

## 设计要点

**列类型推断**

- 全是整数且无空 → `int64` 数组
- 全是数字（可能有空）→ `float64` 数组，空位置是 `NaN`
- 否则 → `Str` 列表

**缺失值不冒充 0**。含缺失的整数列提升为 `float64` + `NaN`，因为 `Int64` 装不下
`NaN`。统计函数自动跳过 `NaN` —— 把空当 0 会让均值、求和全部静默算错。

**缺失标记认 10 种写法**：空串、`?`、`NA`、`N/A`、`null`、`NULL`、`NaN`、`nan`、`#N/A`。
真实 CSV 里「没有值」远不止空字符串一种写法 —— R 导出 `NA`、pandas 可能写 `NaN`、
Excel 手工表常见 `?` 和 `N/A`。**只认空串会让这些列整列退化成文本**，而文本列无法参与
统计：一个 `?` 就毁掉一列。

这不是假想问题：ISLR 的 `Hitters.Salary`（322 行里 59 个 `?`）就是这么炸的 ——
���列被当成文本，`(cangjie::max salary)` 直接失败。

**按字节扫描，不是按字符**。UTF-8 续字节落在 `0x80..0xBF`，而 CSV 分隔符都是 ASCII，
不可能出现在续字节位置 —— 所以按字节扫描不会把汉字劈开，且省掉解码开销。

**引号内允许换行**（RFC 4180）。这正是不能"按行读文件"的原因：一个逻辑行可能跨多个
物理行，状态机必须跨 64KB 读块维持 `inQuotes`。

**与 `xisp_json` 的分工**：本模块只做 CSV，不做 JSON —— JSON 已有独立模块
`ystyle::xisp_json`，重复实现只会让两条解析路径的转义规则逐渐分叉。

## 许可

MIT
