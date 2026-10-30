# 健康资料注册入口（health-entry）

「家族修真录」进入游戏前的健康资料注册入口：上传长辈的体检报告照片 → 视觉模型识别 → 确定性规则引擎换算成游戏初始角色状态。

游戏侧如何接这份数据，见 [INTEGRATION.md](./INTEGRATION.md)。

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

4. 浏览器打开 http://127.0.0.1:8000 ，上传 `样本体检报告.png` 测试识别。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `index.html` | 前端页面（上传、识别、确认初始状态） |
| `server.py` | Flask 服务（托管页面 + 3 个接口） |
| `recognizer.py` | 调用视觉模型识别报告（默认阿里云百炼 `qwen3-vl-plus`） |
| `rules.py` | 确定性规则引擎：健康指标 → 游戏属性 / 五行 |
| `sample-baseline.json` | 一次真实识别的输出示例（即游戏侧要接的格式） |
| `样本体检报告.png` | 测试用样本报告 |

## 接口

- `GET /api/v1/health` —— 识别引擎状态
- `POST /api/v1/records/parse` —— 上传图片 data_url，返回 `document` + `game_projection`
- `POST /api/v1/game/baseline` —— 把确认后的 baseline 保存到 `baselines/`

## 安全

`.env` 含密钥，已写入 `.gitignore`，不要提交。
