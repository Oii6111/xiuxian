# 健康资料接入像素游戏

项目位置：`F:\godot\xiuxian2`。本次仅下载并同步 GitHub 的 `health-entry/`，基于主分支提交 `1f356a098e335713957bc0b7af71816db8c28995`。`rules.py` 与该提交一致，未调整健康量化权重，未合并远程其他游戏、美术或场景。

## 当前流程

每次启动先登录或注册子女账号，再显示独立的本人角色和两个家人位置。旧玩家角色经确认导入后归回本人；选择已确认档案的家人后直接进入仙村。新家人先填写基本资料，再打开所选老人的健康资料页，姓名、年龄、性别和关系自动带入；页面显示当前代填对象。上传报告或填写文字 → 单独确认本次资料使用 → 分析预览 → 确认属性 → 进入仙村。可在资料页选择修仙形象，返回后保留同一位家人的输入。

新版入口取消了五行和护持任务。游戏保存 `character_state`、`readiness`、可选的 `attribute_notes` 和 `evidence`，以及必要元数据。身体系统与属性对应关系沿用 `health-entry/MAPPING.md`。悟性类字段在界面中按新版命名为洞察、心志、身法、气运；目前保留数值，不新增这四项的战斗机制。

## 在本机运行

1. 在 `health-entry/.env` 填写 `LLM_API_KEY`，模型保持 `LLM_MODEL=qwen3-vl-plus`。使用工作空间密钥时，地址应与控制台提供的地址对应，见 `.env.example`。不要把密钥发到聊天或提交到 GitHub。
2. 通过 Godot 打开并运行 `project.godot`，先选择或添加家人。新建后进入该家人的资料页；已有角色可从家人卡片“补充健康资料”或“健康档案 / 五项属性”继续。
3. 游戏会尝试通过 PATH 的 `python` 自动启动 `health-entry/server.py`。若连接失败，双击 `health-entry/start.bat`，回游戏点“重新连接”。可通过环境变量 `XIUXIAN_HEALTH_PYTHON` 指定 Python 路径。
4. 选择资料并勾选授权后分析。仅文字资料直接走规则引擎，不调用模型；有图片时才调用配置的视觉模型。填写 `.env` 后无需重启，点击重新连接即可刷新配置。
5. 检查最终角色数值，确认后保存并进入仙村。界面不展示数值公式或属性计算依据。确认前不会更新角色；修改输入后必须重新分析。

未上传图片时显示“上传报告照片后在此预览”，不会展示角色头像或示例图。病史与用药页提示为“可上传体检报告、病历或用药单照片”。

图片支持 PNG / JPEG / WebP，每次最多 6 张，每张最多 10 MB、合计最多 30 MB。暂不直接支持 PDF，可先导出为图片。文字病史、用药各最多 4000 字。

游戏界面不再提供添加示例或离线样例按钮，也不显示相关引导。仓库样例仅保留给开发检查，可像普通文件一样自行选择上传。新增识别字段 `medications[].brand`，通用名和商品名分开保存供规则读取；规则只按通用名、用法及用途匹配，商品名不参与属性映射。每条指标、病史、用药按最长关键词只归入一个系统，避免重复影响属性。旧存档中的模拟档案仍可兼容读取；创建页只能通过本次资料分析和明确确认生成状态。

本机 Python 为 `E:\anaconda3\python.exe`，依赖已就绪；dotenv 的本地补装目录为被 Git 忽略的 `health-entry/.deps/`。队友的电脑应先运行：

```powershell
python -m pip install -r health-entry/requirements.txt
```

## 请求和确认

服务只监听 `127.0.0.1:8000`。

- `GET /api/v1/health`：身份为 `xiuxian-health-entry`，`api_version: 3` 和 `source_revision: "1f356a0"`；返回配置状态与模型名。游戏在上传前验证身份和版本。
- `POST /api/v1/records/parse`：新版格式 `{data_urls: [], profile: {name, relation, age, sex}, history_text, medications_text}`。姓名、年龄、性别和关系均须提供；年龄为 1—120 的整数，性别为男或女。界面与接口均校验必填项，缺失时不调用模型。仍接受旧版单图 `data_url`，方便兼容。图片经模型结构化后与文字合并，再调用原版 `rules.build_projection()`。
- 返回 `record_id`、`game_projection`、`recognition_mode`（`live` 图片模型识别 / `text` 文字规则计算）、确认的 `display_name`。不把文字模式说成模型识别。
- `POST /api/v1/game/baseline`：`{record_id, recognition_mode, baseline_locked: true}`。服务使用内存中原始规则结果确认，忽略客户端改写的属性。返回 `{mode, baseline_id, baseline}`。30 分钟后或服务重启后需要重新分析。重复确认同一记录返回同一档案。
- 离线样例明确使用 `sample` 模式。网页入口已同步新版字段，并接到同样的确认规则。

游戏适配器不重复缩放接口输出：`hp_max` 直接作为生命上限，`attack` 作为普攻基础伤害，`spirit` 作为灵力上限，`stamina` 作为体力上限。防御沿用现有减伤和护盾规则。初始化满生命。旧版 0—100 模拟档案保留原来的换算，避免破坏旧角色。

姓名、年龄、性别、与子女的关系作为家人基本资料保存；家人姓名与游戏修仙称号分开。HUD 和场景显示修仙称号，确认健康档案不覆盖已有称号。报告图片和完整报告原文不写角色存档。属性依据按新接口保留，可能包含对应病史、指标和药名，因此存档仍应作为个人资料保管，不提交到仓库。

## 模型连接与错误提示

模型请求默认使用 `LLM_USE_SYSTEM_PROXY=auto`：通义千问官方接入点和本机服务直连，其他兼容服务沿用系统代理。可在本地 `.env` 明确设置 `true`（系统代理）或 `false`（直连）。此设置按请求读取，不改 Windows 全局代理，HTTPS 证书校验保持启用。

本机曾出现系统代理转发导致 TLS 提前断开，而相同配置直连官方模型接口正常的问题，因此不能把统一的“模型调用失败”直接解释为密钥有误。当前服务分别返回安全的错误代码与提示：`network_tls`、`network_proxy`、`network_timeout`、`network_connect`，以及 `upstream_http_401` 等模型响应状态。日志只记录错误代码或异常类型，不记录密钥、请求头、报告图片、原始上游响应或私人报告内容。

模型地址以百炼控制台对应地域、业务空间的配置为准，不根据密钥前缀自动改地址。官方说明见 [API Key 配置](https://help.aliyun.com/zh/model-studio/get-api-key/) 和 [视觉模型调用](https://help.aliyun.com/zh/model-studio/qwen-vl-compatible-with-openai)。

## 保存与兼容

`GameState.apply_health_baseline()` 完整校验后整体替换，保留 Boss 首通、成绩、技能解锁、修为和计划。档案锁定后不能通过旧模拟按钮手改属性，可补充资料重新生成档案。健康档案只展示最终属性，不提供属性依据的查看入口；接口附带的属性说明可作为内部数据保留。

当前外层 schema 8 分别保存注册账号、本人角色与最多两位家人，每位家人内部保留完整 schema 6 游戏状态和 `health_baseline`。旧单角色档案经导入确认后备份为 `*-before-accounts-v8.json` 并保留为本人角色，不占家人位置。历史 schema 5 增加了 `health_baseline`，更早版本已有的迁移备份继续保留；当前游戏统一保留完整的家人迁移前备份。旧的接口档案即使 HP 大于 100 也保持存量能力，新档案按新版上限读取。确认写盘先写临时文件，再替换正式存档；失败时恢复原属性和姓名。

编辑器存档为 `output/local-save.json`；运行版本为 Godot 的 `user://songfeng_pixel_progress.json`。服务确认文件位于被忽略的 `health-entry/baselines/`。服务不开放 `.env`、源码或确认文件的静态读取。密钥、生成档案、缓存、`.deps` 均已忽略。

当前面向桌面本地开发；导出给队友时需提供独立的 `health-entry` 服务目录和 Python 环境。尚未制作联网服务或打包安装器。

## 验证方式

`python tests/test_health_entry.py` 覆盖后端契约、模型错误、多图、文字资料和确认。`tests/health_entry_test.gd` 配合 `python tests/health_fixture_server.py`（端口 8001）验证原生界面的 HTTP 流程、初始属性、姓名、修改输入保护、存档迁移与取消。这部分固定使用测试模型响应，不能当作真实大模型调用成功的证明；文字计算使用当前真实规则引擎。

Godot 测试添加 `-- --preview --skip-intro`，不会写玩家存档。`tools/health_service_check.gd` 检查游戏能否启动并连接真正的本地服务，不上传图片、不调用模型。

当前家人选择与代填页面截图见 `output/30-family-selector.png`、`output/32-family-health.png`。`tests/entry_startup_test.gd` 不使用跳过启动标记，验证启动先选家人、旧进度保留、已确认角色直接继续，以及形象选择返回同一位家人的资料页。

## 家人隔离与代填草稿

每次资料页绑定打开时的 GameState 和家人 ID；HTTP 返回和确认写入前检查上下文。分析期间先完成或返回取消后才能切换。取消后的迟到响应不写入任何家人，保存失败回滚属性、姓名和基本资料。首次确认的抽卡依据按家人分别固定。

本次运行内的未完成文字与图片路径按家人保留，重新进入同一位家人时恢复；不会跨家人显示，也不写入游戏存档，退出游戏后清除。每次重新打开都需要重新勾选本次资料使用确认。`tests/family_test.gd` 覆盖两人独立每日奖励、装备与首通隔离、迁移、切换恢复、代填确认与失败回滚。
