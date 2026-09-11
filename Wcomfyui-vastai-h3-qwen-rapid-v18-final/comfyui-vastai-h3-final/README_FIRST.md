# Vast.ai + ComfyUI：MiniMax H3 + Qwen Rapid AIO v18（Diffusers 适配版）

这是在原部署包基础上做的适配版。**图片编辑链路已从原来的 Qwen-Image-Edit-2511 + Lightning LoRA，替换为你指定的 `jldavid/Qwen-Rapid-AIO-v18-NSFW-diffusers`。**

## 已替换的图片编辑链路

- Rapid transformer：`jldavid/Qwen-Rapid-AIO-v18-NSFW-diffusers`
- 基础兼容组件：`Qwen/Qwen-Image-Edit-2511`
  - processor / tokenizer
  - Qwen2.5-VL-7B text encoder
  - Qwen Image VAE
  - FlowMatch scheduler
- **不再下载**原方案的 `qwen_image_edit_2511_fp8mixed.safetensors`
- **不再下载**原方案的 `Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors`
- Rapid AIO v18 已经把加速器/LoRA 合并进 transformer，因此不应再叠加原 Lightning LoRA。

目标模型页面说明它是从 Phr00t Rapid-AIO v18 NSFW 版本提取、转换成 Diffusers transformer 格式，基于 Qwen-Image-Edit-2511，并面向 4-step 推理。 https://huggingface.co/jldavid/Qwen-Rapid-AIO-v18-NSFW-diffusers?not-for-all-audiences=true

## 为什么没有强行塞回原生 ComfyUI KSampler

你指定的模型是 **Diffusers transformer**，不是原方案那种 ComfyUI 原生 checkpoint。直接把它伪装成 `diffusion_models/*.safetensors` 会产生参数映射/量化/采样器兼容风险。

因此本包采用更稳妥的适配：

1. ComfyUI 主环境继续保持原 H3 基线，不混装第二套 Diffusers。
2. 部署脚本创建独立 `/workspace/qwen_rapid_venv`。
3. 固定 `diffusers==0.40.0`、`transformers==5.3.0`。
4. 在独立 worker 中运行官方 `QwenImageEditPlusPipeline`。
5. ComfyUI workflow 通过本包自带的 `QwenRapidAIOV18Edit` 节点调用 worker。
6. worker 常驻，首次加载后不会每张图重复加载 20B transformer。
7. 使用 `enable_model_cpu_offload()`，以 48GB 级 GPU 为部署基线。

Diffusers 0.40.0 已包含 Qwen Image/Edit 支持；官方文档也提供 `QwenImageTransformer2DModel` 的加载方式。 https://github.com/huggingface/diffusers/releases

## Vast.ai 建议

- NVIDIA GPU：**48GB VRAM 起步**
- RAM：>=64GB
- 磁盘：>=120GB（只算这套 Qwen + H3 模型，实际建议 >=250GB 留缓存/输出）
- Linux amd64
- 镜像：`vastai/comfy:v0.35.0-cuda-13.2-py312`

## 部署

```bash
cd /workspace/comfyui-vastai-h3-final
bash deploy_comfyui_vastai_h3.sh
bash /workspace/run_comfyui.sh
```

部署脚本会：

- 检查 Python / PyTorch / CUDA / NVIDIA driver / ComfyUI
- 安装 `aria2`
- 保持 H3 原模型和 H3 workflow 不变
- 创建独立 Qwen Rapid Diffusers venv
- 安装锁定的 Diffusers / Transformers / Accelerate
- 下载 Qwen-Image-Edit-2511 的**非 transformer**兼容组件
- 下载你指定的 Rapid AIO v18 transformer
- 安装本包自带 ComfyUI custom node
- 安装 Qwen Rapid workflow
- 对 H3 模型做 SHA256 校验
- 做 Qwen Rapid 静态文件/依赖检查

## Qwen Rapid workflow

导入：

`workflows/qwen_rapid_aio_v18_diffusers.json`

默认：

- 4 steps
- true CFG = 1.0
- 1 张参考图
- 另有 2 个可选参考图输入

Rapid AIO v18 原项目明确推荐 4-step、1 CFG，并建议 `euler_ancestral/beta`。但原生 ComfyUI KSampler 的这个组合不能在 Diffusers 中逐项一比一复现；本适配使用 QwenImageEditPlusPipeline 支持的 FlowMatch scheduler + 4 steps，因此**这是运行时适配，不声称 sampler 数值完全等价**。 https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO

## 重要：模型下载体积

Qwen-Image-Edit-2511 完整仓库约 57.7GB，其中原始 transformer 约 40.9GB；本包故意不下载这份原始 transformer，因为它会被指定的 Rapid AIO v18 transformer 替换。官方 2511 的 text encoder 约 16.6GB。 https://huggingface.co/Qwen/Qwen-Image-Edit-2511

因此本包实际 Qwen 下载量明显低于“完整 2511 + Rapid transformer”双份方案。

## 实机验收

本包可以做完整的**静态兼容检查**，但当前没有你的 Vast GPU 实例，因此不能在本地替你完成真实 20B 权重加载/4-step CUDA 推理。

部署后首次运行 Qwen workflow 时，worker 会把日志写到：

`/workspace/qwen_rapid_runtime/worker.log`

如果首次加载失败，优先查看该日志，而不要升级 ComfyUI/PyTorch。

H3 与 Qwen Rapid 使用两个隔离运行层，避免为 Qwen Diffusers 升级 Transformers/Diffusers 后破坏 H3/ComfyUI。
