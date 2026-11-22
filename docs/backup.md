# `.moye` 备份与恢复

状态：Windows 已实现备份导出、恢复准备和启动前原子替换；Android 代码路径已接入，运行验证待真机。

## 1. 使用方式

设置 → 备份与恢复：

- **导出 .moye 备份**：选择目录，生成 `MOYE-backup-YYYYMMDD-HHmmss.moye`。
- **从 .moye 恢复**：选择备份文件，校验通过后会在下次启动时替换书库。

恢复不会在阅读过程中直接覆盖数据库。校验成功后，当前书库保持不变，直到应用退出并重新启动。

## 2. 包内容

```text
manifest.json
database/library.db
books/<book files>
covers/<cover images>
attachments/<annotation screenshots>
```

不包含 `cache/`、`logs/`、`backups/`，也不会把绝对路径写入包内。

`manifest.json` 记录：

- 格式版本
- 应用版本
- 数据库 schema 版本
- 创建时间
- 书籍数量
- 每个文件的相对路径、大小和 SHA-256

## 3. 导出流程

1. 使用 SQLite 在线 backup API 生成一致性数据库快照。
2. 扫描 `books/`、`covers/`、`attachments/` 中的普通文件，排除临时文件。
3. 逐个计算 SHA-256，写入 manifest。
4. 使用流式 ZIP 编码写入目标 `.part` 文件。
5. 写入完成后重命名为 `.moye`。

## 4. 恢复流程

### 准备阶段（应用运行中）

1. 读取 ZIP 和 manifest，拒绝符号链接、绝对路径、`..` 路径和未知目录。
2. 按 manifest 解压到 `backups/restore-pending/`。
3. 逐个校验文件大小和 SHA-256。
4. 在临时目录中打开数据库，检查：
   - schema 版本
   - `PRAGMA integrity_check`
   - `PRAGMA foreign_key_check`
   - 数据库引用的书籍/封面/标记截图是否存在
5. 保留 `manifest.json` 作为待恢复标记。

### 启动阶段（打开数据库之前）

1. 如果存在 `restore-in-progress.json`，先把安全保护目录中的旧数据滚回去。
2. 如果存在 `backups/restore-pending/`，再次校验后执行替换。
3. 把旧的 `database/`、`books/`、`covers/`、`attachments/`、`cache/trash/` 移到
   `backups/pre-restore-<timestamp>/`。
4. 把待恢复目录移动到应用根目录。
5. 创建空的 `cache/trash/`，删除待恢复目录和进行中标记。

替换失败会尽量恢复旧目录；`restore-in-progress.json` 用于处理进程在目录替换中途被强制结束的情况。

## 5. 安全边界

- 恢复包不能包含绝对路径、`..`、符号链接或未知目录。
- 恢复包必须包含 `database/library.db`，且数据库 schema 不能高于当前应用。
- 恢复失败不修改当前数据库；当前数据保留在 `backups/pre-restore-*`。
- 备份不加密；`.moye` 包含私人书籍和笔记，请按私人文件保管。
- V1 只做手动全量备份，不做增量、云同步、自动备份。

## 6. 当前限制

- 恢复需要重启墨页。
- Windows 已通过服务层测试；Android 文件选择/写目录路径尚未真机验证。
- 旧数据安全目录目前不会自动清理，便于人工回滚。
- ZIP 解压没有针对超大压缩包的配额限制，V1 依赖用户选择可信的本地备份。
