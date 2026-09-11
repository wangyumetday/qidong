# Workflows

## `qwen_rapid_aio_v18_diffusers.json`

Image-edit workflow for `jldavid/Qwen-Rapid-AIO-v18-NSFW-diffusers`.

It uses the included `QwenRapidAIOV18Edit` custom node. The node runs the
author's Diffusers-compatible transformer together with the compatible
Qwen-Image-Edit-2511 processor/text encoder/VAE/scheduler stack.

Default: 4 steps, true CFG 1.0, one reference image. The node also exposes
two optional additional reference-image inputs.

Important: the source Rapid AIO v18 project recommends native ComfyUI
`euler_ancestral/beta`; Diffusers does not provide a 1:1 mapping of that
KSampler combination, so this adapted workflow uses the supported
`QwenImageEditPlusPipeline` FlowMatch scheduler. This is an intentional
runtime adaptation rather than a claim of sampler-identical output.
