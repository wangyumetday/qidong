# Qwen Rapid AIO v18 Diffusers bridge

This node intentionally runs the Hugging Face Diffusers pipeline in a dedicated
venv so the H3/ComfyUI Python environment is not mixed with a second Diffusers stack.

Model:
- `jldavid/Qwen-Rapid-AIO-v18-NSFW-diffusers`
- base components: `Qwen/Qwen-Image-Edit-2511`

The target repository supplies the Rapid AIO v18 transformer; the official
2511 repository supplies the compatible processor/tokenizer/text encoder/VAE/
scheduler components required by the Diffusers pipeline.

The worker stays alive after first load and uses CPU offload for 48GB-class GPUs.
