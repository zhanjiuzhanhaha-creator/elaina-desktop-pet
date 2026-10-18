# 第三方项目与素材

本项目复用已有桌宠资源及以下免费组件。各依赖的许可仅适用于其自己的代码、模型或资源；不自动覆盖本仓库的角色图片与自有代码。

| 项目 | 用途 | 上游许可与来源 |
| --- | --- | --- |
| Windows WPF | 原生桌面窗口和动画；使用系统组件 | [dotnet/wpf](https://github.com/dotnet/wpf)，MIT；Windows 系统组件同时受其分发条款约束 |
| llama.cpp b11718 | 可选 Windows CPU 本地推理服务 | [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp/releases/tag/b11718)，MIT |
| Qwen3-0.6B-GGUF | 可选 Windows 中文短聊模型 | [Qwen 官方模型](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF)，Apache-2.0 |
| WebLLM 0.2.86 | 可选浏览器 WebGPU 推理 | [mlc-ai/web-llm](https://github.com/mlc-ai/web-llm)，Apache-2.0 |
| Qwen3-0.6B-q4f16_1-MLC | 可选浏览器中文短聊模型 | [MLC 量化模型](https://huggingface.co/mlc-ai/Qwen3-0.6B-q4f16_1-MLC)，基于 [Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B)，Apache-2.0 |
| GitHub Pages Actions | 可选静态网站部署 | [checkout](https://github.com/actions/checkout)、[configure-pages](https://github.com/actions/configure-pages)、[upload-pages-artifact](https://github.com/actions/upload-pages-artifact)、[deploy-pages](https://github.com/actions/deploy-pages)，MIT |

Windows 模型及运行时不随源码提交。`desktop/local-chat/provenance.json` 记录固定版本、下载来源和 SHA256；该目录保留 llama.cpp 与 Qwen 的许可原文。浏览器实际使用的模型标识与资源路径以 `dist/ai.js` 为准；模型权重由访问者主动启用后从上游获取，适用相应模型页面与上游分发条款。

人物形象、原始参考图与其派生图片的相关权利仍属于各自权利人。本项目是个人兴趣创作，未声称获得角色官方授权，也不为这些图片提供 MIT / Apache 等通用再分发许可。

本仓库没有新增覆盖整个项目的开源许可证。若需要复用自有代码或图片，请先向维护者确认适用范围；第三方组件按其原有许可处理。
