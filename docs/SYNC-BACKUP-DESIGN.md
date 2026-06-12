# 可插拔同步与备份实施设计

## 目标

把当前“CloudKit-ready 双 store”落成一套**可插拔**的同步 / 备份架构：

1. **保留现有原则**：同步读者数据，不同步书籍正文与本地 embedding。
2. **把 iCloud 降级为 provider**，而不是写死在 `AppStores` 里。
3. **先交付用户可用的第三方路径**：用户可选任意系统文件夹（iCloud Drive / Dropbox / OneDrive / Google Drive / SMB / NAS 等）保存快照。
4. **为后续自建 Empty Cloud / Passkey / Walrus 留接口**，并先落一个兼容 HTTPS snapshot API 的 server client 壳层。

---

## 当前代码基线

已存在：

- `Empty/Models/AppStores.swift`
  - synced store：`Book / Highlight / ReadingSession / VocabEntry / StudyCardEntry / Bookmark / MemoryItem`
  - local store：`Chapter / Chunk / ParagraphTranslation / MemoryEmbedding`
- `Empty/Models/Book.swift`
  - `fileRelativePath` 与 `coverThumbnailData` 在 synced store
- `Empty/Services/BookFileStore.swift`
  - 书文件落在 App Container，本身**不参与同步**

这意味着同步边界已经是对的；需要改的是**provider 选择、快照 schema、用户入口**。

---

## 不变式

1. **不同步正文**
   - 不同步：`Chapter` / `Chunk` / `ParagraphTranslation` / `MemoryEmbedding`
   - 只同步 / 备份：读者状态与衍生摘要
2. **跨 store 仍只靠 `Book.id`**
3. **第三方文件夹首发定义为“快照备份 / 手动恢复”**
   - 不承诺实时双向合并
   - 真实实时同步留给后续 Empty Cloud / 自建 server provider
4. **未来身份与存储解耦**
   - Passkey / Wallet 不与存储 provider 绑死

---

## 架构分层

### 1. 实时同步 provider

负责持久化容器的“同步开关”与能力声明。

首发 provider：

- `localOnly`
- `cloudKit`

后续 provider：

- `emptyCloud`
- `customServer`

### 2. 快照备份 provider

负责把 synced store 的中立快照写到外部目标。

首发 provider：

- `folder`
- `serverSnapshot`

后续 provider：

- `s3`
- `webdav`
- `walrus`

### 3. 身份 provider（后续）

- `anonymousDevice`
- `passkeyAccount`
- `zkLoginSui`
- `suiPasskeyWallet`

本阶段不接真实账号体系，只在设计上留位。

---

## 中立数据 schema

新增 `SyncSnapshot` 及 record DTO；它们是 provider-neutral 的交换层。

### 进入快照的模型

- `Book`
- `Highlight`
- `ReadingSession`
- `VocabEntry`
- `StudyCardEntry`
- `Bookmark`
- `MemoryItem`

### 不进入快照的模型

- `Chapter`
- `Chunk`
- `ParagraphTranslation`
- `MemoryEmbedding`

### `Book` 特别说明

快照保留：

- 标题 / 作者 / 语言
- `position`
- `progressFraction`
- `cachedHeroRecap`
- `coverThumbnailData`
- `fileRelativePath`

但 **不包含源 EPUB/PDF 文件本身**。恢复到另一台设备时，如果该设备没有对应导入文件，书仍可显示元数据与封面，但正文不可读；这与当前 CloudKit 语义一致。

---

## 用户流

### A. 实时同步

入口：`SyncSettingsView`

- 关闭同步（本机）
- iCloud 同步

切换时：

- 保存 `SyncSettings`
- 重建 `ModelContainer`
- 根视图用新的 container 重载

### B. 第三方文件夹备份

入口：`SyncSettingsView`

- 选择文件夹
- 立即备份
- 恢复最新备份
- 移除文件夹目标

选中的文件夹可以是 Files / File Provider 支持的任意位置：

- iCloud Drive
- Dropbox
- OneDrive
- Google Drive
- SMB / NAS
- 本地 On My iPhone / On My Mac

首发语义：

- 备份文件名固定：`empty-reader-backup.json`
- “恢复”是 **merge/upsert**，不删除本地缺失项
- 冲突策略：**用户主动恢复的快照优先**


### C. Empty Cloud / 自建 Server 快照

入口：`SyncSettingsView`

- 填 `Base URL`
- 填 `Namespace`
- 可选 `Bearer Token`
- 保存目标
- 测试连接（`GET /v1/health`）
- 上传快照（`PUT /v1/reader-snapshots/{namespace}/latest`）
- 恢复最新（`GET /v1/reader-snapshots/{namespace}/latest`）

当前语义：

- 这仍是 **snapshot backup / restore**，不是 live sync mode
- token 留空 = 无鉴权 server
- token 非空 = `Authorization: Bearer …`
- 恢复仍然是 **merge/upsert**

### D. HTTP 契约（当前 client 期待）

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/v1/health` | 200 即视为可连通；可返回 `{ status, service, features }` |
| `PUT` | `/v1/reader-snapshots/{namespace}/latest` | 请求体为 `SyncSnapshot` JSON；header 含 `X-Empty-Device`、`X-Empty-Schema-Version` |
| `GET` | `/v1/reader-snapshots/{namespace}/latest` | 返回 `SyncSnapshot` JSON |

---

## 本阶段落地文件

### 新增

- `Empty/Services/SyncSettings.swift`
  - 存储 live sync provider、folder target、server target
- `Empty/Services/AppSession.swift`
  - App 级状态：`ModelContainer`、sync settings、切换 provider、folder/server target 持久化
- `Empty/Services/SyncSnapshot.swift`
  - provider-neutral snapshot schema、capture / merge
- `Empty/Services/SyncBackupProvider.swift`
  - 快照备份 provider 抽象
- `Empty/Services/FolderBackupProvider.swift`
  - folder bookmark 解析、写入 / 读取快照
- `Empty/Services/ServerSnapshotClient.swift`
  - 兼容 Empty snapshot API 的 HTTPS client
- `Empty/Views/SyncSettingsView.swift`
  - 同步与备份 UI

### 修改

- `Empty/Models/AppStores.swift`
  - `makeContainer(syncMode:ephemeral:)`
- `Empty/EmptyApp.swift`
  - 由固定 `let container` 改为 app session 驱动的可重建 container
- `Empty/Views/Mac/MacRootView.swift`
  - 增加“同步与备份”入口
- `Empty/Views/IOSLibraryScreen.swift`
  - 增加“同步与备份”入口

---

## 本阶段不做的事

### Empty Cloud / 自建 server **live sync**

原因：还没有 cursor / delta / 冲突合并的真实后端契约。

本阶段只落 **server snapshot client**，不把它伪装成实时同步。

### Passkey / 账号体系

原因：需要 session / challenge / key envelope 设计。

### Walrus / Sui wallet

原因：

- 现成官方路径以 TS 为主
- Swift 原生 passkey wallet 成本高
- MemWal 适合作为导出 / 便携层，不适合作为首个主同步后端

---

## 后续阶段

### Phase 2 — Empty Cloud / Custom Server live sync

- `ServerSyncProvider`
- Passkey 登录
- 变更 cursor / delta push-pull
- 冲突合并与设备 tombstone
- 对象存储放快照与 blob

### Phase 3 — Passkey + Wallet

- Passkey 先做 Empty 账号登录
- 若需要 Sui 身份，优先评估 `zkLogin`
- 真正 native Sui passkey wallet 后置

### Phase 4 — Walrus

首选定位：

- 便携 ReaderMemory 导出
- 加密备份目标

不是首个主同步通道。

---

## 验收标准

本阶段完成后：

1. 应用能在 **本机 / iCloud** 间切换实时同步模式。
2. 用户能选择任意系统文件夹作为备份目标。
3. 用户能配置兼容 Empty snapshot API 的 HTTPS server，并测试连接。
4. 用户能把 synced store 导出为快照，并从文件夹 / server 恢复。
5. 快照恢复不会引入正文 / chunk / embedding。
6. 现有单测与平台构建继续通过。
