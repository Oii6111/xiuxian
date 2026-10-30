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

4. 浏览器打开 http://127.0.0.1:8000 ，先填基本信息，再上传 `样本体检报告.png`（可多张）测试识别；没图片也可以只用文字病史 / 用药生成。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `index.html` | 前端页面（上传、识别、确认初始状态） |
| `server.py` | Flask 服务（托管页面 + 3 个接口） |
| `recognizer.py` | 调用视觉模型识别报告（默认阿里云百炼 `qwen3-vl-plus`） |
| `rules.py` | 确定性规则引擎：具体指标 + 病史 + 用药 → 游戏属性（按身体系统对应） |
| `MAPPING.md` | 数据筛选与映射模型说明（哪些数据被采用、如何对应属性） |
| `sample-baseline.json` | 一次真实识别的输出示例（即游戏侧要接的格式） |
| `样本体检报告.png` | 测试用样本报告 |

## 接口

- `GET /api/v1/health` —— 识别引擎状态
- `POST /api/v1/records/parse` —— 接收多张图片 `data_urls` + 文字 `profile`/`history_text`/`medications_text`，返回 `document` + `game_projection`
- `POST /api/v1/game/baseline` —— 把确认后的 baseline 保存到 `baselines/`

## 安全

`.env` 含密钥，已写入 `.gitignore`，不要提交。
