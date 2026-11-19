package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 分组聚合（group-by）
 *
 * ## 为什么需要它
 *
 * 教师工作流里看「不同物种的花瓣长度差多少」、分析师看「各地区的销量分布」，
 * 第一步都是**按类别把数据切开**。没有分组能力时只能手动 `filter` 一遍遍扫全表，
 * 类别一多就退化成 O(类别数 × 行数)。
 *
 * 一次遍历分组是 O(行数)，这是这里实现的方式。
 *
 * ## 返回什么结构
 *
 * **alist**：`[[key, values] …]`，按类别**首次出现的顺序**排列。
 *
 * 没有返回 `HashMap`，是因为 alist 有确定顺序 —— 报告和图表都依赖顺序稳定，
 * 而 HashMap 的迭代顺序不保证。另外 alist 直接就能被 `map` / `filter` 处理：
 *
 * ```lisp
 * (map (lambda (kv) (list (car kv) (cangjie::mean (cadr kv))))
 *      (cangjie::group-by species petal_length))
 * ```
 */

/** 分组键：统一成字符串（数值键用其十进制表示） */
func keyOf(v: LispValue): String {
    match (v) {
        case Str(s) => s
        case Int(i) => "${i}"
        case Float(f) => "${f}"
        case Boolean(b) => if (b) { "true" } else { "false" }
        case _ => v.toString()
    }
}

/** 从列表或 ndarray 提取分组键 */
func labelsOf(v: LispValue, who: String): Array<String> {
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray =>
                    let out = ArrayList<String>()
                    var i: Int64 = 0
                    while (i < a.length()) {
                        out.add(keyOf(a.at(i)))
                        i++
                    }
                    out.toArray()
                case _ => throw IllegalArgumentException(
                    "${who} 的分组键需要列表或 ndarray，得到外部值 ${e.typeName}")
            }
        case Cons(_) | Nil =>
            let out = ArrayList<String>()
            var cur = v
            while (true) {
                match (cur) {
                    case Cons(c) =>
                        out.add(keyOf(c.car))
                        cur = c.cdr
                    case Nil => break
                    case _ => throw IllegalArgumentException(
                        "${who} 的分组键列表结构不完整")
                }
            }
            out.toArray()
        case _ => throw IllegalArgumentException(
            "${who} 的分组键需要列表或 ndarray，得到 ${v.toString()}")
    }
}

/** 一次性遍历分组的中间结果 */
class Grouped {
    let keys: Array<String>
    let groups: Array<Array<Float64>>

    init(keys: Array<String>, groups: Array<Array<Float64>>) {
        this.keys = keys
        this.groups = groups
    }
}

/**
 * **一次遍历**完成分组（O(n)），不是"对每个类别扫一遍全表"（O(k·n)）
 *
 * 类别按首次出现的顺序输出 —— 这是有意的：报告和图表都依赖顺序稳定，
 * 而 `HashMap` 的迭代顺序不保证。
 */
func groupValues(labels: Array<String>, values: Array<Float64>): Grouped {
    if (labels.size != values.size) {
        throw IllegalArgumentException(
            "group-by：分组键 ${labels.size} 个，值 ${values.size} 个，长度不一致")
    }
    let index = HashMap<String, Int64>()
    let keyList = ArrayList<String>()
    let bucketList = ArrayList<ArrayList<Float64>>()
    var i: Int64 = 0
    while (i < labels.size) {
        let k = labels[i]
        var slot: Int64 = -1
        match (index.get(k)) {
            case Some(id) => slot = id
            case None => ()
        }
        if (slot < 0) {
            slot = keyList.size
            index.add(k, slot)
            keyList.add(k)
            bucketList.add(ArrayList<Float64>())
        }
        bucketList[slot].add(values[i])
        i++
    }
    let groups = ArrayList<Array<Float64>>()
    for (b in bucketList) {
        groups.add(b.toArray())
    }
    Grouped(keyList.toArray(), groups.toArray())
}

/** 构造 Lisp 列表 */
func listOf(items: Array<LispValue>): LispValue {
    var v: LispValue = Nil
    var i = items.size - 1
    while (i >= 0) {
        v = consValue(items[i], v)
        i--
    }
    v
}

/** 把分组结果变成 alist：`[[key, values] …]` */
func groupedToLisp(g: Grouped): LispValue {
    let pairs = ArrayList<LispValue>()
    var i: Int64 = 0
    while (i < g.keys.size) {
        let pair = listOf([
            LispValue.Str(g.keys[i]),
            LispValue.External(ndarrayFromFloats(g.groups[i]))])
        pairs.add(pair)
        i++
    }
    listOf(pairs.toArray())
}
