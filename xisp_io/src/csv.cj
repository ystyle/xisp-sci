package ystyle::xisp_io

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.fs.*
import std.convert.*
import std.math.*

/**
 * 流式 CSV 读取器
 *
 * ## 为什么必须流式
 *
 * 一次性 `File.readFrom` 把整个文件读进内存，再解析成二维字符串表 —— 一个 2GB 的
 * CSV 会先占 2GB 字节、再放大成更多字符串对象，直接 OOM；而且"只想看前 10 行"
 * 也要付全部代价。
 *
 * 这里按 **64KB 块**读、边读边解析，**内存占用与文件大小无关**。
 *
 * ## 为什么按字节而不是按字符
 *
 * UTF-8 的多字节序列里，续字节落在 `0x80..0xBF`，而 CSV 的分隔符
 *（`,` `"` `\r` `\n`）都是 ASCII，**不可能出现在续字节的位置**。所以可以安全地
 * 按字节扫描、按字节累积字段，最后 `String.fromUtf8` 还原 —— 不会把一个汉字劈开。
 *
 * ## RFC 4180
 *
 * - 逗号分隔；字段可用双引号包裹
 * - **引号内允许换行** —— 这正是不能"按行读文件"的原因：状态机必须跨块维持 `inQuotes`
 * - 引号内的 `""` 表示一个双引号
 * - `CRLF` / `LF` / `CR` 都算行结束
 * - 文件开头 UTF-8 BOM 忽略
 * - 全空行跳过
 */

const CSV_BUF_SIZE: Int64 = 65536
const BYTE_DQUOTE: UInt8 = 34
const BYTE_COMMA: UInt8 = 44
const BYTE_CR: UInt8 = 13
const BYTE_LF: UInt8 = 10

class CsvReader {
    private let file: File
    private let buffer: Array<UInt8>
    private var bufPos: Int64
    private var bufLen: Int64
    private var eofReached: Bool
    private var closed: Bool

    // 解析状态（跨块保持）
    private var inQuotes: Bool
    private var started: Bool
    /** 已读出但尚未处理的字节（用于一对字节的前瞻，避免回退缓冲的跨块问题） */
    private var pending: Int64
    private var fieldBytes: ArrayList<UInt8>
    private var rowFields: ArrayList<String>

    init(path: String) {
        this.file = File(path, OpenMode.Read)
        this.buffer = Array<UInt8>(CSV_BUF_SIZE, repeat: 0)
        this.bufPos = 0
        this.bufLen = 0
        this.eofReached = false
        this.closed = false
        this.inQuotes = false
        this.started = false
        this.pending = -1
        this.fieldBytes = ArrayList<UInt8>()
        this.rowFields = ArrayList<String>()
    }

    func close(): Unit {
        if (!this.closed) {
            this.file.close()
            this.closed = true
        }
    }

    private func fill(): Unit {
        let n = this.file.read(this.buffer)
        if (n <= 0) {
            this.eofReached = true
            this.bufLen = 0
            this.bufPos = 0
        } else {
            this.bufLen = n
            this.bufPos = 0
        }
    }

    /** 取下一个字节；末尾返回 -1（0 是合法字节，所以不能用 0 表示结束） */
    private func nextByte(): Int64 {
        if (this.pending >= 0) {
            let v = this.pending
            this.pending = -1
            return v
        }
        if (this.bufPos >= this.bufLen) {
            if (this.eofReached) {
                return -1
            }
            this.fill()
            if (this.bufPos >= this.bufLen) {
                return -1
            }
        }
        let v: Int64 = Int64(this.buffer[this.bufPos])
        this.bufPos++
        v
    }

    /** 把刚读出的字节放回（只用于单字节前瞻） */
    private func putBack(b: Int64): Unit {
        this.pending = b
    }

    /** 第一次读之前处理 BOM；直接看缓冲头，避免"读了再退"的边界问题 */
    private func setup(): Unit {
        if (this.started) {
            return
        }
        this.started = true
        if (this.bufPos >= this.bufLen && !this.eofReached) {
            this.fill()
        }
        if (this.bufLen >= 3) {
            let b0: Int64 = Int64(this.buffer[0])
            let b1: Int64 = Int64(this.buffer[1])
            let b2: Int64 = Int64(this.buffer[2])
            if (b0 == 0xEF && b1 == 0xBB && b2 == 0xBF) {
                this.bufPos = 3
            }
        }
    }

    private func endField(): Unit {
        this.rowFields.add(String.fromUtf8(this.fieldBytes.toArray()))
        this.fieldBytes = ArrayList<UInt8>()
    }

    /** 收走当前行；全空行返回 None，让调用方继续读下一行 */
    private func takeRow(): Option<Array<String>> {
        let fields = this.rowFields.toArray()
        this.rowFields = ArrayList<String>()
        if (fields.size == 1 && fields[0].size == 0) {
            return None
        }
        Some(fields)
    }

    /**
     * 取下一行；`None` **只**表示已到末尾（空行在内部跳过）
     *
     * 返回的字段已解开引号与 `""` 转义，不含引号本身。
     */
    func nextRow(): Option<Array<String>> {
        if (this.closed) {
            return None
        }
        this.setup()
        while (true) {
            let raw = this.nextByte()
            if (raw == -1) {
                // EOF：还有未收尾的内容就当成最后一行
                if (this.rowFields.size > 0 || this.fieldBytes.size > 0) {
                    this.endField()
                    match (this.takeRow()) {
                        case Some(f) => return Some(f)
                        case None => return None
                    }
                }
                return None
            }
            let b: UInt8 = UInt8(raw)
            if (this.inQuotes) {
                if (b == BYTE_DQUOTE) {
                    let nb = this.nextByte()
                    if (nb == -1) {
                        this.inQuotes = false
                    } else {
                        let nbv: UInt8 = UInt8(nb)
                        if (nbv == BYTE_DQUOTE) {
                            this.fieldBytes.add(BYTE_DQUOTE)
                        } else {
                            this.inQuotes = false
                            this.putBack(nb)
                        }
                    }
                } else {
                    this.fieldBytes.add(b)
                }
                continue
            }
            if (b == BYTE_DQUOTE) {
                this.inQuotes = true
            } else if (b == BYTE_COMMA) {
                this.endField()
            } else if (b == BYTE_LF) {
                this.endField()
                match (this.takeRow()) {
                    case Some(f) => return Some(f)
                    case None => ()
                }
            } else if (b == BYTE_CR) {
                // 可能是 CRLF：吃掉紧跟的 LF
                let nb = this.nextByte()
                if (nb != -1) {
                    let nbv: UInt8 = UInt8(nb)
                    if (nbv != BYTE_LF) {
                        this.putBack(nb)
                    }
                }
                this.endField()
                match (this.takeRow()) {
                    case Some(f) => return Some(f)
                    case None => ()
                }
            } else {
                this.fieldBytes.add(b)
            }
        }
        // 循环只能靠 return 退出；这行让编译器确信所有路径都有返回值
        return None
    }
}

/**
 * Lisp 侧可见的游标
 *
 * 用完必须 `csv-close` —— 否则文件句柄要等 GC 才回收。
 *
 * ```lisp
 * (define cur (cangjie::csv-open "big.csv"))
 * (define header (cangjie::csv-next cur))     ; 表头行
 * (cangjie::csv-each cur (lambda (row) (println row)))
 * (cangjie::csv-close cur)
 * ```
 */
public class CsvCursor <: LispExternal {
    internal let reader: CsvReader
    internal var exhausted: Bool
    internal var closed: Bool

    init(path: String) {
        this.reader = CsvReader(path)
        this.exhausted = false
        this.closed = false
    }

    public prop typeName: String {
        get() { "csv-cursor" }
    }

    public func display(): String {
        if (this.closed) {
            "#<csv-cursor closed>"
        } else if (this.exhausted) {
            "#<csv-cursor exhausted>"
        } else {
            "#<csv-cursor>"
        }
    }

    /** 取下一行；`None` = EOF（此后不再读） */
    internal func next(): Option<Array<String>> {
        if (this.closed || this.exhausted) {
            return None
        }
        let r = this.reader.nextRow()
        if (r.isNone()) {
            this.exhausted = true
        }
        r
    }

    internal func close(): Unit {
        if (!this.closed) {
            this.reader.close()
            this.closed = true
        }
    }
}
