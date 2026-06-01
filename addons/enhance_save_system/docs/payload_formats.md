# Enhanced Save System：Payload 格式说明

## 概览

存档插件现在支持两种正文编码后端：

- `json_compact`
- `variant_binary`

两者都继续复用同一套外层能力：

- `_meta` 头
- 原子写入
- 压缩
- 加密
- 版本迁移
- `peek_meta()` / 编辑器槽位预览

也就是说，切换 payload 格式不会绕开 `SaveWriter`，只是改变正文 `body` 的编码方式。

## 什么时候用 `json_compact`

默认推荐使用 `json_compact`。

适合场景：

- 当前项目的数据大部分还是 `Dictionary / Array / String / Number / Bool`
- 希望兼容旧存档最稳
- 希望调试时更容易 dump 成可读 JSON
- 需要 split-modules

特点：

- 正文不再写带缩进的 pretty JSON，而是紧凑 JSON
- 如果未启用压缩和加密，会直接写成纯文本 JSON 文件
- 如果启用压缩或加密，会写成“头部 JSON + 正文 bytes”的容器格式

## 什么时候考虑 `variant_binary`

`variant_binary` 是可选增强，不是默认推荐。

更适合：

- 单个存档已经明显变大
- 自动存档频繁，想进一步缩小正文体积
- 你不在意正文本身可读

注意：

- 第一版只支持主文件模式
- `split_modules_enabled = true` 时会自动回退到 `json_compact`
- 依然会保留 `_meta` 头，所以编辑器和槽位列表仍可预读时间、版本、加密方式等信息

## 兼容策略

当前读写链兼容四类文件：

1. 旧纯文本 JSON
2. 旧容器格式：`header JSON + JSON body`
3. 新紧凑 JSON 格式
4. 新 `variant_binary` 格式

规则：

- 旧文件只要能读，就视为兼容成功
- 不做一次性批量迁移
- 文件被重新保存时，才会按当前 `payload_format` 落盘为新格式

## `_meta` 关键字段

新增字段：

- `payload_format`
- `body_encoding_version`

已有字段继续保留：

- `version`
- `saved_at`
- `game_version`
- `encryption_type`
- `compression`
- `split_modules`

## 调试建议

如果你想保留一个人工可读副本，可以开启：

- `SaveSystem.debug_pretty_json_dump_enabled`

这会额外生成一个 `.debug.json` 调试文件，不影响正式存档读写。

## 当前建议

对当前项目，建议顺序是：

1. 默认先用 `json_compact`
2. 用 demo / bench 测真实 `global` 和 `slot` 数据
3. 只有当体积或读写耗时真的成为问题时，再切到 `variant_binary`
