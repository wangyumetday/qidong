# Model sources

## Image editing — replaced

- Rapid AIO v18 NSFW Diffusers transformer:
  https://huggingface.co/jldavid/Qwen-Rapid-AIO-v18-NSFW-diffusers?not-for-all-audiences=true
- Base Qwen-Image-Edit-2511 compatibility components:
  https://huggingface.co/Qwen/Qwen-Image-Edit-2511

Only the base model's processor/tokenizer/text encoder/VAE/scheduler are downloaded. Its 40.9GB transformer is excluded because the Rapid AIO v18 transformer replaces it.

## Image editing — removed from old plan

- `Comfy-Org/Qwen-Image-Edit_ComfyUI` `qwen_image_edit_2511_fp8mixed.safetensors`
- `lightx2v/Qwen-Image-Edit-2511-Lightning` `Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors`

These are no longer referenced by the deployment script or Qwen workflow.

## Video — retained

- https://huggingface.co/Comfy-Org/MiniMax-H3
- https://huggingface.co/bilmemne13/1/blob/main/H3_Motion_BoosterV2.safetensors
- https://huggingface.co/matheus58457/minimax-h3-loras/blob/main/MysticXXX_MMH3-V4.safetensors
