# Reader Notes Backup Design

当前版本没有云同步、账号系统、自建 server，也不接文件夹同步。产品先回到单机阅读：所有数据在本机 SwiftData。备份只做一个显式的 `.empty-notes` 读者笔记包。

## 目标

1. **本机优先**：没有网络、没有账号、没有 entitlement，阅读体验不受影响。
2. **备份小而清楚**：只导出用户自己创造或选择保留的内容。
3. **正文不上包**：EPUB/PDF 文件、章节正文、译文缓存、embedding、API Key 永远不进备份。
4. **先本地文件，后云盘**：现在只做可审计的本地 export/import；Finder、外置盘、iOS Files 或第三方云盘只是承载文件的位置，不是同步系统。

## Store 边界

### Reader Data Store（会进备份包）

- `Book`
- `Highlight`
- `ReadingSession`
- `VocabEntry`
- `StudyCardEntry`
- `Bookmark`
- `MemoryItem`

这些是小体量、用户生成、丢失成本高的数据：阅读位置、高亮批注、单词、卡片、ReaderMemory。

### Local Derived Store（不备份）

- `Chapter`
- `Chunk`
- `ParagraphTranslation`
- `MemoryEmbedding`

这些数据都能从导入文件或 reader data 重建，或体积 / 隐私边界不适合进入备份包。

## Runtime

- `AppSession` 只创建本机 `ModelContainer`。
- `AppStores` 仍保留两组 SwiftData configuration，历史 reader-data 文件名继续叫 `Synced.store`，但运行时固定 `cloudKitDatabase: .none`。
- `BackupSettingsView` 提供导出 / 导入 `.empty-notes`，并解释本机状态与数据边界。
- macOS sandbox user-selected files 权限改为 read-write，保证 save panel 能写出备份包。
- `Empty.entitlements` 现在是空 entitlement 文件，不再要求云能力签名。

## 已实现

`ReaderNotesBackupStore` 导出一个单文件 JSON `.empty-notes`：

```json
{
  "manifest": { "schemaVersion": 1, "exportedAt": "...", "appVersion": "..." },
  "books": [],
  "highlights": [],
  "readingSessions": [],
  "vocabEntries": [],
  "bookmarks": [],
  "studyCards": [],
  "memoryItems": []
}
```

导入策略：

- 每条记录保留稳定 `id` 和 `bookID`，同 id 记录做合并更新。
- 导入不会删除本机已有记录。
- 子记录按 `bookID` 重新挂回书籍；找不到书时保留 orphan 记录。
- `MemoryItem` 用 `updatedAt` 做保守冲突处理：本机更新时跳过旧备份。
- 备份包不包含书文件。`Book.fileRelativePath` 只是元数据，恢复到另一台设备后仍需要重新导入书文件才能阅读正文。

## 已移除

- Apple 云同步路径。
- 文件夹 JSON 快照备份 / 恢复。
- Empty Cloud / 自建 server snapshot API。
- live delta / cursor / tombstone 协议。
- mutation journal、自动重试、后台调度、冲突策略。
- Passkey 账号壳层。

这不是云同步。它只是一个可移动、可检查、可恢复的读者笔记包。
