# Elder Health Sidecar：OpenClaw Weixin 挂载层

这个小插件只做一件事：把 **OpenClaw Weixin 私聊** 的文字、语音转写和已经 staging 到本机的图片，转发到上一级目录的 Flask 健康侧车 `/api/v1/elder/message`。老人侧不会看到游戏字段。

## 为什么用 `before_dispatch`

OpenClaw 的 typed hook 在普通模型分发前执行；插件返回 `{ handled: true, text: "..." }` 后，当前消息由健康侧车直接回复，不再落到普通模型。这样红旗症状、照片确认和服药记录都能先经过确定性安全规则。插件需要 `allowConversationAccess`，只应安装在你们自己的 Gateway 上。

## 本地安装（在运行 OpenClaw Gateway 的机器上）

```bash
openclaw plugins install --link ./prototype/openclaw-health-hook --force
openclaw plugins enable elder-health-sidecar
```

在 OpenClaw 配置里加入：

```json
{
  "plugins": {
    "entries": {
      "elder-health-sidecar": {
        "enabled": true,
        "config": {
          "sidecarUrl": "http://127.0.0.1:8000",
          "sidecarToken": "与 ELDER_SIDECAR_TOKEN 相同的内部令牌",
          "defaultElderId": "elder_demo_001",
          "elderIdMap": { "wx_user_xxx": "elder_demo_001" },
          "familyShareDefault": false,
          "allowRemoteMedia": false,
          "failClosed": true
        },
        "hooks": { "allowConversationAccess": true }
      }
    }
  }
}
```

不要把微信二维码登录当作家庭授权。建议再用本项目的 `family-link` 一次性绑定码和服务端白名单限制老人/子女关系；当前 Weixin 插件版本的标准 pairing 能力可能不完整。

修改代码后执行 `openclaw plugins reload elder-health-sidecar`，再用 `openclaw plugins inspect elder-health-sidecar --runtime --json` 检查 typed hook 是否注册。

## 媒体处理边界

插件优先读取 OpenClaw 已 staging 的本地 `media.path`，转成临时 data URL 发给侧车；不默认抓取任意远程 URL。音频若已有 `transcribed` 字段，只把转写传给侧车。原始媒体不写入侧车 SQLite。

## 演示消息

1. 发：`我今天吃完药了` → 侧车回复确认问题。
2. 回：`是` → 侧车写入一条已确认健康事件。
3. 发一张报告/药盒照片 → 侧车识别候选，要求“识别没问题”或“不对”。
4. 发：`胸口很痛，喘不上气` → 直接给急救提示，不调用普通模型。

> `index.ts` 是按当前 OpenClaw typed hook 文档写的适配器；不同 Gateway 版本若字段名有差异，只需调整 `textOf` / `mediaToAttachment`，不要把医疗规则移到插件里。
