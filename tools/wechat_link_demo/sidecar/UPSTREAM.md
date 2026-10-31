# 老人端源码来源

以下五个文件保持下载时的原样：`elder_assistant.py`、`model_provider.py`、`recognizer.py`、`medical_rag.py`、`medical_kb.json`。

来源：Oii6111/xiuxian，提交 `bf5ad8580729351bfb91fac68eecec5dd2acb13d`，目录 `wechat-sidecar/`。

本地文字联调由上级目录 `sidecar_adapter.py` 显式安装适配扩展，不覆盖上游文件。完整原始下载、桥接器及 C 后端参考源码位于开发工作区的独立评审目录；本游戏没有将远程主分支覆盖合并进来。

此目录用于本机合成数据演示。正式老人微信服务应由 D 同学审阅扩展、对齐公共后端与授权后，在自己的服务中接入；不要将此目录当作已部署的真实微信通道。
