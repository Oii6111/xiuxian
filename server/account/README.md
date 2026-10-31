# 账号服务

使用 Python 3 标准库，无需另装依赖。游戏首次提交注册或登录时，会验证服务身份并尝试自动启动本机服务。用户名为 3—24 位字母、数字或下划线；密码为 8—128 位；昵称最多 10 个字。

```powershell
python server/account/server.py
```

默认监听 `127.0.0.1:8010`。SQLite 数据保存在 `server/account/data/accounts.sqlite3`，包含加盐密码哈希、会话摘要和旧档归属记录。不要删除该数据库或提交到仓库。测试使用独立临时数据库，不写入真实账号。

接口：`GET /api/v1/health`；`POST /api/v1/auth/register`（username/password/display_name/avatar）；`POST /api/v1/auth/login`；`GET /api/v1/auth/session`；`POST /api/v1/auth/logout`；`POST /api/v1/auth/claim-legacy`。会话通过 Authorization Bearer 传递，令牌仅保存在客户端内存中，退出后失效。

配置环境变量：`XIUXIAN_ACCOUNT_URL` 设置客户端服务地址；远程地址必须使用 HTTPS。本地自动启动可用 `XIUXIAN_ACCOUNT_PYTHON` 指定 Python 路径；服务端支持 `--port`、`--db` 或 `XIUXIAN_ACCOUNT_PORT`、`XIUXIAN_ACCOUNT_DB`。

当前是本机账号服务；未部署公网，也没有跨设备存档同步。游戏文件按注册账号 ID 分别存放，所有家人位置均归当前子女账号管理。

验证：`python tests/test_accounts.py -v` 检查密码校验、会话和旧档归属。`tests/account_test.gd` 配合临时账号服务运行注册、换号、独立存档与导入流程；`tests/account_autostart_test.gd` 验证首次启动账号服务。
