# Version lock — adapted package

| Component | Locked value | Notes |
|---|---|---|
| Vast Docker image | `vastai/comfy:v0.35.0-cuda-13.2-py312` | Existing H3/ComfyUI baseline |
| ComfyUI | `v0.35.0` | Existing baseline |
| PyTorch | `2.10.0` / cu130 | Existing baseline |
| NVIDIA driver floor | `595.45.04` | Existing baseline |
| workflow templates | `0.11.57` | Existing H3 baseline |
| Qwen Rapid Diffusers | `0.40.0` | Dedicated venv |
| Qwen Rapid Transformers | `5.3.0` | Dedicated venv; verified released PyPI version |
| Accelerate | `>=1.10,<2` | Dedicated venv |
| Rapid model | `jldavid/Qwen-Rapid-AIO-v18-NSFW-diffusers` | User-selected model |
| Rapid base | `Qwen/Qwen-Image-Edit-2511` | Processor/tokenizer/text encoder/VAE/scheduler only |
| Rapid LoRA | none | v18 acceleration/NSFW merges are already in transformer |
| Qwen VAE | `Qwen/Qwen-Image-Edit-2511/vae` | Required companion component |
| Qwen text encoder | `Qwen/Qwen-Image-Edit-2511/text_encoder` | Required companion component |
| Qwen processor/tokenizer | `Qwen/Qwen-Image-Edit-2511/processor`, `tokenizer` | Required companion components |
| Qwen sampling | 4 steps, true CFG 1.0 | Rapid AIO intended fast path |

## Compatibility decision

The target repository is a Diffusers transformer, not a native ComfyUI checkpoint. The package therefore does **not** convert or rename it into `models/diffusion_models`. It runs through a dedicated Diffusers worker and a ComfyUI bridge node.

The target model card identifies it as a 20B F8_E4M3 transformer and says it is based on Qwen-Image-Edit-2511 and optimized for 4-step inference.

## Reproducibility note

The user supplied the model's `main` URL rather than an immutable commit. The deployment script therefore resolves the current `main` snapshot at deployment time. The installed snapshot revision is recorded by Hugging Face Hub's local snapshot metadata.

The package intentionally does not invent a SHA256 for the remote Rapid transformer without downloading and hashing the actual file.
