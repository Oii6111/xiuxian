# 主仓库 GitHub Pages 部署

GitHub Pages 发布由 [部署工作流](../.github/workflows/deploy-pages.yml) 从主仓库 `main` 构建的 Godot Web 客户端。入口采用 `project.godot` 配置的主场景，仓库首页地址直接加载游戏。工作流把 Web 导出包上传为 Pages 构建产物，仓库源码分支无需存放 `.pck` 或 `.wasm`。

## 首次启用

1. 合并包含游戏改动和部署工作流的 PR。
2. 主仓库维护者在 [Pages 设置](https://github.com/Oii6111/xiuxian/settings/pages) 中，将 **Build and deployment → Source** 设为 **GitHub Actions**。
3. 在 [Actions](https://github.com/Oii6111/xiuxian/actions/workflows/deploy-pages.yml) 打开 **Publish game to GitHub Pages**，选择 `main` 后点击 **Run workflow**。后续推送到 `main` 会自动部署。
4. 部署完成后打开 [游戏首页](https://oii6111.github.io/xiuxian/)，检查登录界面和问道长廊。通过 [发布提交号](https://oii6111.github.io/xiuxian/source-commit.txt) 核对实际部署的源码版本。

## 正式服务

Pages 托管静态客户端。正式账号、存档、微信绑定和灵宠服务仍由项目后端提供。正式后端需要正常提供 HTTPS 服务，并允许 Pages 浏览器来源 `https://oii6111.github.io` 跨源访问。浏览器发送的来源包含协议和主机，省略项目路径 `/xiuxian/`。游戏 API 的 `CORS_ORIGINS` 用逗号分隔允许的来源。服务依赖与部署方法见 [联调说明](BCD_INTEGRATION.md)。

如果 Pages 加载出登录界面，但注册、登录或微信绑定失败，应同时检查后端状态、浏览器网络请求以及目标服务的跨源响应。主仓库工作流的 [官方说明](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages) 可用于排查发布配置。
