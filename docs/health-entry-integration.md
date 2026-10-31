# 本地健康原型与像素游戏的兼容接缝

本目录的识别和确定性规则仍属于健康域。C 正式合并规则见 [PR #5 健康域边界](https://github.com/Oii6111/xiuxian/blob/165daf573932590b4f1e352e125e52309388dfed/health-entry/INTEGRATION.md)。当前适配核对见 [merge-compatibility-review.md](merge-compatibility-review.md)。

## 数据边界

报告图片、病史、药名、模型提取内容、`source_document`、`attribute_notes`、`evidence` 留在健康服务。游戏不能读取健康服务保存的完整 baseline 文件，也不能把它作为 C 游戏 API 请求或客户端 Store。

当前旧像素原型通过独立白名单投影返回游戏数值，`projection_version=legacy-pixel-v1`。投影仅含 `character_state` 固定数值字段、守护准备度、版本、不透明档案 ID、锁定状态和当前显示姓名。提供方、模型、健康解释和证据特征不写游戏存档。

这是旧本地原型的安全兼容层。产品 v2 为五属性，当前原型为十属性；转换规则与 C 的权威初始化接口仍未约定。本地适配器不代替该契约，也不向 C 提交完整 baseline。

## 运行与使用

1. 在 `health-entry/.env` 填写 `LLM_API_KEY`，默认 `LLM_MODEL=qwen3-vl-plus`。密钥只在服务端使用，不提交到 Git。
2. 运行游戏并登录当前本地账号服务，选择本人或家人后进入基础状态填写。姓名、年龄、性别、关系均必填；代填须确认授权。
3. 选择 PNG/JPEG/WebP 报告照片，最多 6 张、每张 10 MB、合计 30 MB；也可提交文字资料。文字病史/用药只在当前健康页和健康请求中使用，不保存到家人状态或游戏存档；页面关闭后清空未提交内容，只恢复已有的基础身份。
4. 预览最终游戏属性，明确确认后保存。游戏内不展示公式或医疗解释。修改输入、切换家人或账号后，旧请求结果不能写入新的上下文。

本机 Python 为 `E:\anaconda3\python.exe`。其他电脑安装 `health-entry/requirements.txt`。游戏尝试启动本地服务；失败可运行 `health-entry/start.bat` 并重新连接。`XIUXIAN_HEALTH_PYTHON` 可指定解释器。

`LLM_USE_SYSTEM_PROXY=auto` 默认让通义千问直连，其他兼容服务沿用系统代理；可显式设为 true/false。不修改 Windows 全局代理，也不关闭 HTTPS 证书校验。网络、TLS、超时与鉴权错误分别提示，日志不输出密钥、原图、原始模型响应或病历原文。

## 接口归属

健康服务监听 `127.0.0.1:8000`，不是 C 游戏服务。

- `GET /api/v1/health`：服务身份、配置状态、API 版本和游戏投影能力版本。
- `POST /api/v1/game/projections/parse`：接收独立健康 UI 的图片/文本；响应仅含记录引用、模式、显示姓名和白名单游戏数值。原始 document、医学解释和 evidence 不返回游戏。
- `POST /api/v1/game/projections/confirm`：按健康服务保存的 record_id 确认原始规则结果，返回白名单投影。重复确认返回同一记录，结果有效期 30 分钟。
- `/api/v1/records/parse`、`/api/v1/game/baseline`：旧健康网页原型内部接口，完整数据仅供健康域使用，不能用来对接 C 或读入游戏。

游戏的 `HealthBaseline.validate()` 是旧数据转游戏投影的兼容适配器。医疗字段不会进入其返回值；`GameState.to_data()` 和家人整体存档另做防御过滤。保存字段保留旧名称 `health_baseline` 是为兼容当前离线存档，内容已是精简游戏投影。

## 旧档清理与导入

游戏 JSON 读档时清理临床解释及原文，再创建只含游戏进度的迁移备份。`tools/migrate_game_privacy.gd` 可一次处理已有游戏档案与备份；它不会触碰健康域 baseline、图片或账号数据库。

旧档解析唯一实现为 `scripts/legacy_saves.gd`。导出版依次查找 `songfeng_pixel_progress.json`、`family_cultivation_demo.json`，编辑器使用 `output/local-save.json`。登录固定实际来源、摘要和认领指纹；清理医疗字段前的归属指纹以不透明引用保留。发现、认领、备份和导入不会各选一个文件。文件被外部修改后要求重新确认。

账号缓存为 schema 8，各角色游戏状态兼容 schema 6。角色、装备、钱包、首通、成绩保留；不重新计算历史游戏属性。旧 bug 造成的空账号可重新提示导入，有进度的账号不自动覆盖。

## 检查

`python tests/test_health_entry.py` 检查健康/游戏接口边界。`tests/privacy_legacy_test.gd` 检查隐私净化与历史路径。`tests/account_test.gd` 使用临时账号数据库验证登录、认领和导入。其余家人、装备、战斗与健康 UI 回归测试继续适用。当前不声称已验证 C 的正式 v2 账号、账本、D 核验和微信链路。
