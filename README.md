# 伊蕾娜的小房间

一只会撒娇、摸头、玩猜拳，还能陪你专注的 Q 版桌宠。仓库包含 Windows 桌面版与无需安装的浏览器体验版。

项目仓库：[zhanjiuzhanhaha-creator/elaina-desktop-pet](https://github.com/zhanjiuzhanhaha-creator/elaina-desktop-pet)。

在线体验：[伊蕾娜的小房间](https://elaina-playroom-tzxser.myworkspace-8830.chatgpt.site)。无需登录，电脑和手机均可打开。

![伊蕾娜小房间的浏览器体验预览](docs/preview.png)

## 可以一起做什么

| 功能 | 浏览器体验 | Windows 桌面版 |
| --- | --- | --- |
| 呼吸、眨眼、微笑、打瞌睡 | 页面内连续动画 | 桌面悬浮动画 |
| 摸摸头、兔耳与爱心 | 点击或触摸按钮；鼠标悬停摸头 | 鼠标摸头、单击兔耳爱心 |
| 撒娇互动、猜拳、称呼与亲密度 | 直接使用 | 直接使用 |
| 自由 AI 短聊 | 可选浏览器本地模型，需要 WebGPU | 可选 CPU 本地模型，需单独下载 |
| 专注与装饰 | 页面内体验 | 原生计时、暂停、记录与星星装扮 |
| 数据保存 | 当前浏览器的本地存储 | 本地 `config.json` |
| 桌面置顶、拖动、登录自启动 | 浏览器不提供这些能力 | 支持 |

无需账号和付费 API 即可使用内置互动。可选模型首次启用需要联网下载，之后在访问者自己的设备上计算。浏览器模型依赖 WebGPU、网络和可用内存；不兼容设备仍可体验全部内置动作与固定互动。

浏览器 AI 使用 WebLLM 0.2.86 与 Qwen3-0.6B 量化模型，需主动点击启用，首次约下载 350–400 MB。优先使用支持 WebGPU 与 `shader-f16` 的桌面 Chrome / Edge；模型加载与推理速度受显卡、内存和网络影响。

验证状态：桌面版自检、网页按钮与规则对话、昵称保存、猜拳、专注暂停与奖励、手机布局均已通过。浏览器 AI 的真实 WebGPU 能力检测通过；首次模型初始化尚未完成端到端验证，当前作为可选体验提供。

## Windows 版

下载整个仓库并解压，双击 `desktop/启动桌宠.cmd`。普通互动使用系统自带 Windows PowerShell 5.1 / WPF，无需安装 Node.js、Python 或模型。

自由聊天的安装、自启动和完整操作见 [桌面版说明](desktop/README.md)。源码不附带模型权重或运行时二进制，安装脚本使用官方来源与 SHA256 校验。

## 本地运行网页

网页为原生 HTML / CSS / JavaScript，`dist` 就是可部署目录，不需要打包或安装 npm 依赖。用任意静态服务器提供 `dist`；例如已装 Python 时，在仓库根目录执行：

```sh
python -m http.server 8080 --directory dist
```

然后访问 `http://localhost:8080`。请通过 HTTP 服务打开，ES 模块与可选 WebGPU 模型不适合直接双击 HTML。

## 发布到 GitHub Pages

仓库已提供 `.github/workflows/pages.yml`，使用 GitHub 官方 Pages Actions。仓库 Settings → Pages → Build and deployment 选择 **GitHub Actions** 后，推送 `main` 分支的网页变更或手动运行工作流即可发布 `dist`。Pages 地址以工作流的实际部署结果为准；这个配置不代表已经启用了 GitHub Pages。

## 目录

```text
dist/                   浏览器体验与图片资源
desktop/                Windows 源码、资源、可选模型安装脚本
.github/workflows/      GitHub Pages 自动发布
THIRD_PARTY_NOTICES.md   第三方项目与角色素材说明
```

称呼、目标、聊天记录、密钥和已下载模型不应提交到仓库；常见本地数据与大文件已加入 `.gitignore`。网页与桌面版不会同步数据，也不向开发者发送聊天内容；浏览器首次加载可选模型会请求第三方资源服务器。

这是个人兴趣作品，与角色官方无关联。角色与原始参考图的权利归相应权利人；本仓库没有为这些素材授予新的开源许可。代码暂未附加通用开源许可证，第三方依赖遵守各自许可，详见 [第三方说明](THIRD_PARTY_NOTICES.md)。
