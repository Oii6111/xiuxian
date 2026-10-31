# 抽卡、账号与家族版本验证

基于主分支 `1f356a0` 整合，使用 Godot 4.7.2 和 Python 3 验证。测试使用隔离存档、临时账号数据库与本地固定健康识别响应，不写入玩家存档或调用真实大模型。

| 检查 | 结果 |
|---|---|
| 抽卡、每日去重、保底、装备、失败回滚 | 59 项通过 |
| 本人/两位老人、代填、切换与存档隔离 | 53 项通过 |
| 注册登录、退出换号、账号文件和旧档归属 | 17 项通过 |
| 启动登录与首次启动账号服务 | 通过 |
| 现有仙村操作 | 45 项通过 |
| 四技能与成长 | 76 项通过 |
| 二十 Boss 长廊 | 76 项通过 |
| 健康界面 HTTP 流程 | 39 项通过 |
| Python 账号服务 | 4 个测试通过 |
| Python 健康接口 | 23 个测试通过 |
| 主分支公共内核 | 80 项通过 |
| 保留的剧情关卡规则 | 640 项通过 |
| 保留的剧情战斗界面 | 162 项通过 |
| 保留的剧情真实键鼠流程 | 23 项通过 |

## 重复运行

先安装 `health-entry/requirements.txt` 中的 Python 依赖。账号服务仅使用 Python 标准库。

```powershell
python tests/test_accounts.py
python tests/test_health_entry.py
& $env:GODOT4 --headless --path . --script res://tests/equipment_test.gd -- --preview --skip-intro --kernel-ephemeral
& $env:GODOT4 --headless --path . --script res://tests/family_test.gd -- --preview --skip-intro --kernel-ephemeral
& $env:GODOT4 --headless --path . --script res://tests/kernel_test.gd -- --preview --skip-intro --kernel-ephemeral
```

`account_test.gd` 和 `health_entry_test.gd` 分别配合临时账号服务、`tests/health_fixture_server.py` 运行，通过环境变量设置测试端口。所有模型响应为固定样例。旧剧情的图形测试加载独立的 `scenes/legacy_campaign_village.tscn`，默认游戏使用 `scenes/main.tscn`。

本版账号服务和钱包为本机演示实现，尚未对接 v2 服务端权威账本、微信结算或跨设备同步，也未验证公网部署。
