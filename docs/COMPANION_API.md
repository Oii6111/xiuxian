# 灵宠与 chatbot 对接约定（v1 草案）

当前实现：四选一、昵称、免费切换、村庄跟随与点击交互、聊天面板、今日任务/家人近况/下一步引导，以及可选 HTTP 聊天适配器。默认使用本地规则向导，未接通微信、云端任务或大模型。

## 游戏入口与保存

- 首次正式登录且未选择灵宠时进入选择页。也可在仙村左侧点击“选择你的灵宠”或“灵宠相伴”。点击地图上的灵宠同样可以聊天。
- 四只 ID：`cloud_fox` 云团小狐、`gourd_dragon` 葫芦小龙、`lotus_bird` 莲叶团雀、`herb_deer` 药草小鹿。
- 选择和昵称存入账号家族文件的根字段 `companion: {id, nickname}`，继续兼容 schema 8。旧档缺少该字段时等待选择；不修改本人/老人位置、装备、灵气、健康属性或试炼进度。
- 聊天历史仅保留本次登录会话的最近 40 条，在内存中按当前角色区分展示。退出账号时清空；不写入游戏存档。
- 当前任务状态来自游戏本地确认记录。未收到记录与“没有做”有区别；微信提交状态将在后续双方确认统一任务接口后接入。

## 开启聊天服务

为启动 Godot 的进程设置 `XIUXIAN_COMPANION_API_URL`，值是**完整 POST 地址**，例如 `https://your-service.example/api/v1/companion/chat`。默认不设置，继续使用仙村向导。正式地址使用 HTTPS；开发时允许 `http://127.0.0.1:端口/...`、`localhost` 或 `[::1]`。

```powershell
$env:XIUXIAN_COMPANION_API_URL = 'http://127.0.0.1:8031/api/v1/companion/chat'
& 'F:\Godot_v4.7.2-stable_win64.exe' --path 'F:\godot\xiuxian2'
```

请求头为 `Content-Type: application/json`。仅设置聊天 URL 时不发送账号令牌。只有双方已约定会话验证方式，且 `XIUXIAN_COMPANION_AUTH_ORIGIN` 显式设置为该服务的源地址（协议、主机、端口，不含路径），才附带 `Authorization: Bearer <游戏会话>`。例如本机测试可设置为 `http://127.0.0.1:8031`；更换主机或端口后不会继承授权。模型密钥保留在服务端。

当前本机账号会话尚不是跨服务通用凭证，正式部署仍需统一验证或增加最小权限令牌交换；不要仅为消除 401 就把 C 登录令牌发给模型供应商。服务端必须验证身份和家庭授权，不能信任请求里的 account_id/member_id。测试夹具接受固定测试会话，仅限本机联调。请求发出后若账号会话、角色或聊天地址改变，旧回复会被丢弃；连接失败仍显示原有本地向导。

## 请求

```json
{
  "schema_version": 1,
  "request_id": "每次发送唯一，重试时按此编号去重",
  "conversation_id": "每次登录会话生成的编号",
  "channel": "godot",
  "account_id": "当前年轻人账号ID",
  "companion": {"id": "gourd_dragon", "nickname": "团团"},
  "message": "下一步做什么？",
  "context": {
    "source": "local_game",
    "as_of_date": "2026-10-31",
    "active_member_id": "self",
    "characters": [{
      "member_id": "self", "label": "我", "kind": "self",
      "has_profile": true,
      "tasks": [
        {"id": "medication", "title": "既有用药计划记录", "status": "not_applicable"},
        {"id": "planned_record", "title": "个人计划坚持记录", "status": "unrecorded"}
      ],
      "reward_recorded": false, "qi": 0,
      "equipment_count": 0, "boss_cleared_count": 0
    }]
  }
}
```

`characters` 包含本人以及已在游戏中同意共享的家人，使用“父亲/母亲”等关系称呼，不发送真实姓名、年龄、报告、健康读数、用药内容、图片和本地路径。任务 status 当前为 `confirmed` / `unrecorded` / `not_applicable`。context 是客户端提示用投影，不能作为服务器验真或发奖依据；正式服务需要查询权威任务库。

## 响应

```json
{
  "request_id": "原样回传",
  "conversation_id": "原样回传",
  "reply": "今天的计划记录暂未收到。实际完成后，可以去记录页面核对。",
  "animation": "talk",
  "actions": [{"id": "record", "label": "查看今日记录"}]
}
```

- `reply`：1—2000 字的普通文字；客户端使用 Label 展示。
- `animation`：`idle`、`talk`、`celebrate`，分别映射到本地预设表现。
- `actions`：最多三个导航按钮；允许 `record`（当前角色记录）、`family`（家庭选择）、`health`（当前档案）、`treasure`（祈愿）、`equipment`（行囊）、`boss`（试炼）。标签最多 16 字。
- 按钮由玩家点击，走现有 UI。回复中的任务完成、奖励、任意路径/脚本等额外字段不执行。任务确认仍在原页面进行，不因聊天直接到账。
- `request_id`、`conversation_id` 必须匹配请求。15 秒超时、网络错误、异常状态码、无效 JSON 或格式错误时，提示连接暂不可用并回到本地向导。
- 关闭面板、切换角色或账号时取消未完成请求；客户端再次核对账号/角色范围，避免把旧回复显示给新角色。

## 与微信同伴后续确认

1. 公共聊天服务的实际地址、请求/响应格式与身份验证方式。
2. 游戏账号与微信老人身份的绑定关系、共享范围、撤回授权处理。
3. 权威任务实例 ID、日期/时区、状态版本，以及任务同步接口；当前本地布尔记录不能直接代表微信审核/结算状态。
4. 同一实例跨微信与游戏提交的去重与结算规则，以及同步失败后的恢复方式。

本次只接入聊天适配器，不自动部署公共服务，也不承诺已完成微信跨设备同步。确认上述约定后，可替换 `companion_client.gd` 的适配部分，保留灵宠形象、选择、动画和聊天界面。

## 本机验证

`tests/companion_test.gd` 验证选宠、保存/失败回滚、旧档兼容、账号归属、任务投影、导航和界面；`tests/companion_api_test.gd` 配合 `tests/companion_fixture_server.py` 验证 HTTP。夹具为固定模拟回复，不调用大模型、不连接微信。
