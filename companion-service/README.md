# 灵宠聊天服务（DeepSeek · deepseek-flash）

把 [docs/COMPANION_API.md](../docs/COMPANION_API.md) 里定义的 v1 聊天契约接到真实大模型。
默认使用 DeepSeek 的 `deepseek-flash`，也可以指向任何 OpenAI 兼容服务。

游戏侧仍然是「可选 HTTP 适配器」：不配置就继续用本地向导，配置后灵宠回答由本服务生成，
但**任务完成、灵气、装备等游戏状态仍只由 C 后端结算**——聊天不会直接发奖。

## 目录

| 文件 | 用途 |
|---|---|
| `server.py` | Flask 服务，实现 `POST /api/v1/companion/chat` 与 `GET /healthz` |
| `.env.example` | 模型与服务配置模板（复制成 `.env` 后填密钥） |
| `tests/test_contract.py` | 契约测试，不联网、不需要密钥 |
| `启动灵宠聊天服务.cmd` | Windows 双击启动 |

## 快速开始

```powershell
cd companion-service
python -m pip install -r requirements.txt
copy .env.example .env
# 编辑 .env，把 LLM_API_KEY 填成 DeepSeek 控制台申请的密钥
python server.py
```

看到下面这行就说明起来了：

```
灵宠聊天服务：http://127.0.0.1:8031/api/v1/companion/chat
provider=openai-compatible model=deepseek-flash base_url=https://api.deepseek.com/v1
```

没有填密钥时会显示 `provider=stub`，返回本地固定话术，用于离线演练整条链路。

## 接到游戏

在**启动 Godot 的那个进程**里设置两个环境变量（`XIUXIAN_COMPANION_AUTH_ORIGIN`
不含路径，用于确认可以把游戏会话发给这个服务）：

```powershell
$env:XIUXIAN_COMPANION_API_URL = 'http://127.0.0.1:8031/api/v1/companion/chat'
$env:XIUXIAN_COMPANION_AUTH_ORIGIN = 'http://127.0.0.1:8031'
& $env:GODOT4 --path .
```

或者直接双击仓库根目录的 `启动试玩-灵宠模型.cmd`，它会先拉起聊天服务再进游戏。

## 配置

| 变量 | 默认值 | 说明 |
|---|---|---|
| `LLM_API_KEY` | 空 | DeepSeek 密钥；空则进入 stub |
| `LLM_BASE_URL` | `https://api.deepseek.com/v1` | OpenAI 兼容根地址 |
| `LLM_MODEL` | `deepseek-flash` | 模型名 |
| `LLM_TIMEOUT` | `20` | 秒；客户端 15 秒放弃，这里必须更短才来得及返回 |
| `LLM_USE_SYSTEM_PROXY` | `auto` | `false` 时忽略环境代理 |
| `COMPANION_SERVICE_TOKEN` | 空 | 设置后要求 `Authorization: Bearer ...`；空时只接受本机回环 |
| `HOST` / `PORT` | `127.0.0.1` / `8031` | 监听地址 |

## 边界与约束

- **动作按钮由本地规则挑选**：模型只负责文字，回复里即使写了 `give_qi` 或"奖励 99999"
  也不会变成按钮或到账。允许的动作只有 `record / family / health / treasure / equipment / boss`。
- **上下文白名单**：只把 `as_of_date`、角色标签、任务标题与状态送入提示词；真实姓名、
  病史、用药内容、体检数值、图片路径在 `validate()` 里就被丢弃。
- **错误一律收敛**：超时、401、坏 JSON 都返回 502 + 通用文案，游戏自动回退本地向导。
- **去重**：相同 `request_id` 直接回放，不重复调用模型。

## 验证

```powershell
cd companion-service
python -m unittest discover -s tests -p 'test_*.py' -v
```

契约测试覆盖：schema 校验、id 回传、动作白名单、回复截断、模型失败收敛、
重放去重、服务凭证、上下文白名单。

真实模型连通性（需要密钥）：

```powershell
curl.exe -s http://127.0.0.1:8031/healthz
curl.exe -s -X POST http://127.0.0.1:8031/api/v1/companion/chat `
  -H "Content-Type: application/json" `
  -d '{\"schema_version\":1,\"request_id\":\"probe-1\",\"conversation_id\":\"conv-1\",\"companion\":{\"id\":\"gourd_dragon\",\"nickname\":\"团团\"},\"message\":\"下一步做什么？\",\"context\":{\"as_of_date\":\"2026-10-31\",\"characters\":[{\"label\":\"我\",\"kind\":\"self\",\"tasks\":[{\"title\":\"用药计划记录\",\"status\":\"unrecorded\"}]}]}}'
```

## 与测试夹具的区别

`tests/companion_fixture_server.py` 是固定回复的回归夹具，供 `tests/companion_api_test.gd`
断言精确文案；本服务是真实联调入口，回复由模型生成，不对固定字符串做断言。
