# Final deployment audit — Qwen Rapid AIO v18 adaptation

## What changed

The original image-edit path was:

`Qwen-Image-Edit-2511 ComfyUI checkpoint + Qwen Lightning 4-step LoRA`

It is now:

`jldavid/Qwen-Rapid-AIO-v18-NSFW-diffusers transformer`
+
`Qwen/Qwen-Image-Edit-2511 processor/tokenizer/text encoder/VAE/scheduler`

The old Qwen ComfyUI checkpoint and old Lightning LoRA are no longer downloaded or referenced by the image-edit workflow.

## Compatibility approach

The selected model is a Diffusers transformer. It is not treated as a native ComfyUI diffusion checkpoint.

A dedicated venv is created:

`/workspace/qwen_rapid_venv`

Locked packages:

- diffusers 0.40.0
- transformers 5.3.0
- accelerate >=1.10,<2
- safetensors >=0.5
- huggingface_hub >=0.34,<2
- Pillow >=10

The Qwen worker is isolated from the main ComfyUI Python environment. This avoids a dependency collision between the H3/ComfyUI stack and the newer Diffusers/Transformers stack.

## Model storage

Qwen Rapid:

`/workspace/qwen_rapid_models/qwen_rapid_aio_v18/transformer`

Qwen base companion components:

`/workspace/qwen_rapid_models/qwen_image_edit_2511`

The base transformer is intentionally excluded.

## Runtime

The worker loads:

`QwenImageTransformer2DModel`

into:

`QwenImageEditPlusPipeline`

and uses:

`enable_model_cpu_offload()`

This is the conservative 48GB deployment path.

## Workflow

`workflows/qwen_rapid_aio_v18_diffusers.json`

The workflow references the bundled custom node:

`QwenRapidAIOV18Edit`

Defaults:

- 4 steps
- true CFG 1.0
- one required reference image
- two optional reference-image inputs

## Sampler compatibility note

The source Rapid AIO v18 project recommends native ComfyUI `euler_ancestral/beta`.

There is no honest 1:1 mapping of that KSampler configuration into the Diffusers API used by the selected model. The adapted implementation therefore uses the pipeline's supported FlowMatch scheduler with the intended 4-step distilled transformer.

This is a deliberate compatibility adaptation, not a claim that the two samplers produce bit-identical results.

## Static checks performed

- ZIP/package structure inspected.
- Original deployment script inspected.
- Original Qwen models/workflow references removed.
- New custom node syntax checked.
- New workflow JSON parsed.
- Deployment script rewritten to install isolated runtime.
- Qwen base/target model directory structure is checked after download.
- Diffusers/Transformers versions are checked before worker launch.
- Existing H3 model SHA256 checks retained.
- H3 workflow LoRA checks retained.

## What still requires real GPU acceptance

The package cannot truthfully claim a successful 20B CUDA inference without access to the final Vast instance.

After deployment, the first Qwen run is the real acceptance test. The worker log is:

`/workspace/qwen_rapid_runtime/worker.log`

If the first inference fails, do not immediately upgrade packages; inspect this log first.
