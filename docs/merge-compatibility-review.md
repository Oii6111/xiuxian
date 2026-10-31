# PR #5 适配核对与 P1/P2 修复

核对目录：`F:\godot\xiuxian2`。参考 [PR #5](https://github.com/Oii6111/xiuxian/pull/5) 的头提交 `165daf573932590b4f1e352e125e52309388dfed`，该 PR 已合并。规则原文见 [C 合并指南](https://github.com/Oii6111/xiuxian/blob/165daf573932590b4f1e352e125e52309388dfed/docs/BACKEND_INTEGRATION.md) 与 [健康域边界](https://github.com/Oii6111/xiuxian/blob/165daf573932590b4f1e352e125e52309388dfed/health-entry/INTEGRATION.md)。

## 已修复 P1：医疗解释进入游戏存档

原路径为：健康服务返回完整解释 → `HealthBaseline.validate()` 保留 `attribute_notes` / `evidence` → `GameState.to_data()` 原样保存 → 本人及家人缓存、迁移备份保留病史和药名。隐藏 UI 中的公式不能阻止这条数据流。

现在有三层约束：

1. 独立健康原型通过 `/api/v1/game/projections/parse` 和 `/api/v1/game/projections/confirm` 返回固定白名单的本地游戏投影；不返回报告原文、`document`、`source_document`、`attribute_notes`、`evidence`、模型解释和提供方元数据。原来的健康原型接口及其完整档案仍留在健康域。
2. `scripts/health_baseline.gd` 只接受游戏数值、版本、不透明档案 ID、姓名等当前本地玩法所需字段。旧完整 baseline 可作为迁移输入，但医疗字段被直接丢弃，不进入正常游戏状态。
3. `scripts/game_save_privacy.gd` 在序列化及读档时再次过滤。`GameState.to_data()`、`FamilyRoster.to_data()`、旧档加载和备份都使用它，防止直接修改内存对象绕过边界。

`tools/migrate_game_privacy.gd` 只处理本项目 `output/`、`output/accounts/`、`user://`、`user://accounts/` 内可识别的游戏 JSON 及其备份；不处理 `health-entry/baselines/`、图片或账号数据库。首次运行检查并清理 11 份旧游戏文档，无失败。清理保留属性、角色、钱包、装备、通关、成绩和登录归属；原有认领指纹通过不透明来源引用保持稳定。

同时移除了 `FamilyRoster.health_drafts`：关闭填写页不再把病史、药名、照片路径存入游戏家人对象。未提交医疗输入随当前页面关闭清空；重新打开只恢复既有的基础身份。保留医疗草稿的后续需求应由独立健康域实现。

这里的 `legacy-pixel-v1` **仅是当前旧像素原型的兼容投影**，不是 C 批准的正式游戏基线接口。十属性到产品 v2 五属性的转换仍待 D/B 明确，并由 C 增加共享契约，不能将此兼容层接入 C 账本当作权威健康结论。

## 已修复 P2：导出版旧档发现与导入来源不一致

`scripts/legacy_saves.gd` 统一历史文件名。导出版依次解析 `user://songfeng_pixel_progress.json`、`user://family_cultivation_demo.json`；编辑器解析 `output/local-save.json`。显式测试路径仍优先。

`FamilyRoster` 在登录时固定实际来源路径和内容摘要；`needs_import`、归属认领指纹、医疗字段清理、备份和导入使用同一来源。后续出现另一个文件不会切换来源，原文件改变或消失会拒绝导入并要求重新确认。已有账号缓存缺失时也不会悄悄绕过认领去加载其他旧档。

旧缺陷曾生成的空账号缓存，如果没有确认过“使用新角色”，会重新提供旧档恢复选项。已确认的新角色、已经导入过的账号、有装备/家人/成长的账号不会被自动覆盖。

## 尚未完成的 C 正式合并接缝

| 范围 | 当前本地原型 | PR #5 约定 | 后续适配 |
| --- | --- | --- | --- |
| 账号 | `server/account` Python、8010、`/api/v1/auth`，注册后客户端直接持有会话，响应 account/token 在顶层 | C Node/TypeScript、8080、`/api/v2/auth`、四段 Result，注册与登录分开 | B 使用 C 的 `GameApi`，按 Result 与会话切换规则接入；不要复制另一套权威账号服务 |
| 角色与状态 | 本人加两位家人的本地 schema 8 缓存，GameState 为整体状态 | `growth.create/list/snapshot/select`，各模块 Store、版本迁移及 WebSocket 快照 | 按 C 角色标识和账号归属重建投影，账号变更清理模块状态 |
| 资源和抽卡 | `GameState.record_task()` / `draw_equipment()` 在本地加减资源并抽取 | C 的任务核验、Ledger 事务、版本规则、幂等命令 | UI 只显示服务端结果，保留原幂等键；正式模式不能以本地结算兜底 |
| 初始健康属性 | 当前保留旧原型十属性及原游戏换算 | 产品 v2 五属性；PR #5 明确暂不接收完整 baseline、不猜测十到五映射 | D/B/C 共同确认白名单投影、版本、角色/赛季和授权引用 |
| 绑定与导入 | 本地代填同意框及 `/api/v1/auth/claim-legacy` | D 独立服务凭证、可信身份和授权版本；C 当前没有该旧档认领端点 | 不能把 checkbox 或本地指纹当作 C 的可信授权；正式导入需 C 明确接口与幂等/归属规则 |

本地目前没有 `scripts/net/game_api.gd`、`scripts/autoload/game_kernel.gd`、`data/kernel/contracts.json` 或 C 的 `server/package.json`。所以不能声称 C 的 `npm run check` 或正式网络接入已通过；本次验证的是当前本地原型与其隐私/迁移修复。

## 验证与交付状态

- Python 健康服务：24 个测试通过，包含游戏响应无医疗解释、健康域仍保留解释、重复确认幂等。
- `privacy_legacy_test.gd`：21 项通过，涵盖内存/序列化/旧档/备份净化、两种历史文件名、路径固定、变化拒绝与空账号恢复。
- 本地临时账号服务：17 项通过；家人 53、装备 59、动作与进度 76、村庄 45、健康 UI 39 项通过。
- 测试使用独立账号数据库；没有上传私人报告，没有改 `.env`，没有重置角色。

最新复检确认已知游戏档案及备份的待清理字段为 0；重复清理不再改写文件，认领指纹保持稳定。

当前工作树仍以 `08bc088` 为本地 HEAD，包含大量未提交修改和未跟踪文件。本次修复尚未提交、推送或合并。正式提 PR 时应先在独立功能分支对齐 C 基线，再按公共服务/模块所有权整理提交；不要直接用旧目录覆盖 C 的内核或服务。
