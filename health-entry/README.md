# 健康资料注册入口（health-entry）

「家族修真录」进入游戏前的健康资料注册入口：先填长辈基本信息（关系、年龄），再上传体检报告 / 病历 / 用药单照片（可多张），视觉模型识别常规指标、病史和用药 → 确定性规则引擎换算成游戏初始角色状态。

游戏侧如何接这份数据，见 [INTEGRATION.md](./INTEGRATION.md)；数据怎么筛选、如何映射成属性，见 [MAPPING.md](./MAPPING.md)。

## 快速运行

1. 安装依赖：

   ```bash
   pip install -r requirements.txt
   ```

2. 复制配置并填入视觉模型密钥：

   ```bash
   copy .env.example .env
   # 编辑 .env，填入 LLM_API_KEY
   ```

3. 启动：

   ```bash
   python server.py
   ```

   Windows 也可以双击 `start.bat`。

4. 浏览器打开 http://127.0.0.1:8000 ，先填基本信息，再上传示例图测试识别（可多张一起传）：`样本体检报告.png`（体检单）、`手写既往病史记录.png`（手写病史）、`四款药品包装展示.png`（药盒）；没图片也可以只用文字病史 / 用药生成。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `index.html` | 前端页面（上传、识别、确认初始状态） |
| `server.py` | Flask 服务（托管页面 + 3 个接口） |
| `recognizer.py` | 调用视觉模型识别报告（默认阿里云百炼 `qwen3-vl-plus`） |
| `rules.py` | 确定性规则引擎：具体指标 + 病史 + 用药 → 游戏属性（按身体系统对应） |
| `MAPPING.md` | 数据筛选与映射模型说明（哪些数据被采用、如何对应属性） |
| `sample-baseline.json` | 一次真实识别的输出示例（即游戏侧要接的格式） |
| `样本体检报告.png` | 测试用样本（体检单） |
| `手写既往病史记录.png` | 测试用样本（手写病史便签） |
| `四款药品包装展示.png` | 测试用样本（四种药盒合影） |

## 接口

- `GET /api/v1/health` —— 识别引擎状态
- `POST /api/v1/records/parse` —— 接收多张图片 `data_urls` + 文字 `profile`/`history_text`/`medications_text`，返回 `document` + `game_projection`
- `POST /api/v1/game/baseline` —— 把确认后的 baseline 保存到 `baselines/`

## 安全

`.env` 含密钥，已写入 `.gitignore`，不要提交。


## 本地游戏桥接补充

服务只监听 `127.0.0.1:8000`，配置热读取。`health` 包含服务身份和 `api_version: 3`。解析返回 `record_id` 与模式 `live`（图像）或 `text`（文字）。确认提交 `{record_id, recognition_mode, baseline_locked: true}`，返回服务端原始规则生成的 `baseline`；不接受客户端手改真实属性。结果保留 30 分钟，重复确认幂等。离线示例使用 `sample`。确认文件只保存游戏状态、显示姓名和属性依据，不保存完整报告。


当前像素游戏接入自提交 `1f356a0`，Godot 启动后直接进入“创建基础状态”，不提供样例快捷入口；样例文件仅保留供开发者自行选择测试。游戏操作说明见 [health-entry-integration.md](../docs/health-entry-integration.md)。

创建状态必须提供 `profile.name`、`profile.age`、`profile.sex`、`profile.relation`；年龄为 1—120 的整数，性别为男或女。缺少必填项会在模型调用前返回 400。Godot 仅显示最终属性，不显示 `attribute_notes` 的公式或依据。

模型网络路由支持 `LLM_USE_SYSTEM_PROXY=auto/true/false`。auto 对通义千问使用直连，其他兼容服务沿用系统代理；不更改 Windows 代理，也不关闭 TLS 校验。网络、超时、鉴权和模型权限错误会分别提示，日志不记录密钥或报告内容。


## 游戏域白名单边界

Godot 改用 `/api/v1/game/projections/parse` 和 `/api/v1/game/projections/confirm`，只接收固定游戏数值与必要引用/版本。医疗解释、病史、药名、evidence 和原文不进入游戏状态或存档。完整 baseline 仅留在本健康服务；它不是 C 的正式游戏 API。详见 [PR #5 适配状态](../docs/merge-compatibility-review.md)。
