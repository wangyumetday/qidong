#!/usr/bin/env bash
set -euo pipefail

# Final Vast.ai deployment for:
#   Qwen-Image-Edit-2511 + MiniMax H3 FL2VA
#   H3_Motion_BoosterV2 + MysticXXX_MMH3-V4
#
# IMPORTANT: start the Vast.ai instance from the exact image below.
# This script intentionally FAILS on a mismatched ComfyUI/PyTorch environment
# rather than replacing system packages and creating a mixed environment.

WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR="${COMFYUI_DIR:-$WORKSPACE/ComfyUI}"
PORT=18188
IMAGE_TAG="v0.35.0-cuda-13.2-py312"
COMFYUI_TAG="v0.35.0"
TEMPLATES_VER="0.11.57"
DRIVER_MIN="595.45.04"

log(){ echo -e "\033[1;32m[DEPLOY]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
die(){ echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ---------- 0. Vast/image and host checks ----------
[[ "${IMAGE_TYPE:-vast}" == "vast" ]] || warn "IMAGE_TYPE 不为 vast；仍继续检查。"
[[ -d "$COMFYUI_DIR" ]] || die "未找到 $COMFYUI_DIR。请使用 Vast.ai 官方镜像 $IMAGE_TAG，而不是普通 PyTorch 镜像。"
command -v python3 >/dev/null || die "python3 不存在"
command -v nvidia-smi >/dev/null || die "nvidia-smi 不存在"
command -v curl >/dev/null || die "curl 不存在"

python3 - <<'PY' || die "Python 不是 3.12.x"
import sys
assert sys.version_info[:2] == (3,12), sys.version_info
print('[OK] Python', sys.version)
PY

# ComfyUI exact checkout when git metadata is available.
if [[ -d "$COMFYUI_DIR/.git" ]]; then
  TAG=$(git -C "$COMFYUI_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)
  [[ -z "$TAG" || "$TAG" == "$COMFYUI_TAG" ]] || die "ComfyUI 不是 $COMFYUI_TAG（当前: ${TAG:-unknown}）"
else
  warn "当前 ComfyUI 没有 .git 元数据；版本由 Vast 官方镜像 + Python/runtime 检查共同确认。"
fi

python3 - <<'PY'
import torch
print('[INFO] torch:', torch.__version__)
print('[INFO] torch.version.cuda:', torch.version.cuda)
assert torch.__version__.split('+')[0] == '2.10.0', torch.__version__
assert torch.version.cuda == '13.0', torch.version.cuda
assert torch.cuda.is_available(), 'CUDA unavailable'
print('[OK] PyTorch 2.10.0 / cu130 / CUDA available')
PY

DRV=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d ' ')
python3 - "$DRV" <<'PY'
import sys

def v(s): return tuple(int(x) for x in s.split('.')[:3])
minimum=(595,45,4)
cur=v(sys.argv[1])
assert cur >= minimum, f'{sys.argv[1]} < 595.45.04'
print('[OK] NVIDIA driver', sys.argv[1])
PY

VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1 | tr -d ' ')
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
log "GPU: $GPU / ${VRAM} MiB"
(( VRAM >= 46000 )) || warn "当前显存低于 48GB。最终方案按 48GB 基线验证，低于该值不保证性能/显存余量。"

# ---------- 1. Tools ----------
if ! command -v aria2c >/dev/null; then
  log "安装 aria2..."
  apt-get update -qq
  apt-get install -y -qq aria2
fi

# ---------- 2. Download acceleration ----------
export HF_XET_HIGH_PERFORMANCE=1
export HF_HUB_DISABLE_TELEMETRY=1
log "HF_XET_HIGH_PERFORMANCE=1"

# ---------- 3. Exact workflow-template package ----------
python3 - <<'PY'
import importlib.metadata as md, subprocess, sys
want='0.11.57'
try:
    got=md.version('comfyui-workflow-templates')
except md.PackageNotFoundError:
    got=''
if got != want:
    subprocess.check_call([sys.executable,'-m','pip','install','--no-cache-dir',f'comfyui-workflow-templates[video]=={want}'])
print('[OK] comfyui-workflow-templates', md.version('comfyui-workflow-templates'))
PY

# ---------- 4. Model download / runtime isolation ----------
download_and_verify(){
  local url="$1" dest="$2" expected="$3"
  mkdir -p "$(dirname "$dest")"
  if [[ -s "$dest" ]]; then
    local got
    got=$(sha256sum "$dest" | awk '{print $1}')
    if [[ "$got" == "$expected" ]]; then
      log "SHA256 OK, skip: $(basename "$dest")"
      return 0
    fi
    warn "已有文件 SHA256 不匹配，删除重下：$(basename "$dest")"
    rm -f "$dest"
  fi
  log "下载：$(basename "$dest")"
  aria2c -c -x 16 -s 16 -k 16M --max-tries=12 --retry-wait=5 \
    --auto-file-renaming=false --allow-overwrite=true --file-allocation=none \
    -d "$(dirname "$dest")" -o "$(basename "$dest")" "$url"
  local got
  got=$(sha256sum "$dest" | awk '{print $1}')
  [[ "$got" == "$expected" ]] || die "SHA256 校验失败：$(basename "$dest")\n期望 $expected\n实际 $got"
  log "SHA256 OK: $(basename "$dest")"
}

M="$COMFYUI_DIR/models"
H3="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main"
H3L1="https://huggingface.co/bilmemne13/1/resolve/8bced197155e4e3b3c65f77f98047adb08cbf58f"
H3L2="https://huggingface.co/matheus58457/minimax-h3-loras/resolve/c7503b2a9253ea3bc6323bdcca460fcc6eb91bc4"

log "===== MiniMax H3 FL2VA ====="
download_and_verify "$H3/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" "$M/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" "e889202c41dafb67b10d67b97f0d8541508036a6090af23425a5c2615d03c47a"
download_and_verify "$H3/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" "$M/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" "35a88d51044231fe332301d7a62aa81e3f2cba62febeb446e2c1e3e0ef76f2c6"
download_and_verify "$H3/vae/minimax_h3_video_vae_fp16.safetensors" "$M/vae/minimax_h3_video_vae_fp16.safetensors" "7c1f131492e7eddacaac9069a61b81bdd39de5cc96561e677c5eab1cdce5e522"
download_and_verify "$H3/vae/minimax_h3_audio_vae_fp32.safetensors" "$M/vae/minimax_h3_audio_vae_fp32.safetensors" "8e505d95dd1561d47abd43d4238fd40d9bb1ae9e147ed0a4cba778d76ae4db48"
download_and_verify "$H3L1/H3_Motion_BoosterV2.safetensors" "$M/loras/H3_Motion_BoosterV2.safetensors" "f6a6897162b921d2b74abe1fdebcd80c8189147e70e0e0738200756c250336c3"
download_and_verify "$H3L2/MysticXXX_MMH3-V4.safetensors" "$M/loras/MysticXXX_MMH3-V4.safetensors" "fc3e856d14c6c19557c888f48662d591e4794e281233ec0d987be5003068afba"

# Qwen Rapid AIO v18 is a Diffusers transformer, not a native ComfyUI
# diffusion_model checkpoint. Keep its Python stack isolated from ComfyUI.
QWEN_ROOT="${QWEN_RAPID_ROOT:-$WORKSPACE/qwen_rapid_models}"
QWEN_BASE="$QWEN_ROOT/qwen_image_edit_2511"
QWEN_RAPID="$QWEN_ROOT/qwen_rapid_aio_v18"
QWEN_VENV="${QWEN_RAPID_VENV:-$WORKSPACE/qwen_rapid_venv}"
mkdir -p "$QWEN_ROOT" "$QWEN_BASE" "$QWEN_RAPID"

log "===== Qwen Rapid AIO v18 Diffusers runtime ====="
if [[ ! -x "$QWEN_VENV/bin/python" ]]; then
  log "创建隔离 venv: $QWEN_VENV"
  python3 -m venv --system-site-packages "$QWEN_VENV"
fi
"$QWEN_VENV/bin/python" -m pip install --upgrade pip setuptools wheel
"$QWEN_VENV/bin/python" -m pip install --no-cache-dir \
  "diffusers==0.40.0" \
  "transformers==5.3.0" \
  "accelerate>=1.10,<2" \
  "safetensors>=0.5" \
  "huggingface_hub>=0.34,<2" \
  "Pillow>=10"

# Only download the non-transformer components from the official 2511 base.
# The 40.9GB base transformer is intentionally excluded because the target
# Rapid AIO v18 transformer replaces it.
"$QWEN_VENV/bin/python" - <<PY
from huggingface_hub import snapshot_download
from pathlib import Path
base=Path(r"$QWEN_BASE")
rapid=Path(r"$QWEN_RAPID")
snapshot_download(
    repo_id="Qwen/Qwen-Image-Edit-2511",
    local_dir=str(base),
    ignore_patterns=["transformer/*"],
)
snapshot_download(
    repo_id="jldavid/Qwen-Rapid-AIO-v18-NSFW-diffusers",
    local_dir=str(rapid),
    allow_patterns=["transformer/*", "README.md", ".gitattributes"],
)
print("[OK] Qwen 2511 base components downloaded")
print("[OK] Qwen Rapid AIO v18 transformer downloaded")
PY

[[ -f "$QWEN_BASE/model_index.json" ]] || die "Qwen base model_index.json missing"
[[ -f "$QWEN_BASE/vae/config.json" ]] || die "Qwen base VAE missing"
[[ -f "$QWEN_BASE/text_encoder/config.json" ]] || die "Qwen base text encoder missing"
[[ -f "$QWEN_BASE/processor/preprocessor_config.json" ]] || die "Qwen base processor missing"
[[ -f "$QWEN_RAPID/transformer/config.json" ]] || die "Qwen Rapid v18 transformer config missing"

# Static import/version test without loading 20B weights.
"$QWEN_VENV/bin/python" - <<'PY'
import diffusers, transformers, torch
from diffusers import QwenImageEditPlusPipeline, QwenImageTransformer2DModel
print("[OK] diffusers", diffusers.__version__)
print("[OK] transformers", transformers.__version__)
print("[OK] torch", torch.__version__, "cuda", torch.version.cuda)
assert diffusers.__version__ == "0.40.0"
assert transformers.__version__ == "5.3.0"
assert hasattr(diffusers, "QwenImageEditPlusPipeline")
assert hasattr(diffusers, "QwenImageTransformer2DModel")
PY

# Install the bundled ComfyUI custom node.
rm -rf "$COMFYUI_DIR/custom_nodes/qwen_rapid_aio_v18"
mkdir -p "$COMFYUI_DIR/custom_nodes"
cp -a "$(cd "$(dirname "$0")" && pwd)/custom_nodes/qwen_rapid_aio_v18" \
  "$COMFYUI_DIR/custom_nodes/qwen_rapid_aio_v18"

# ---------- 5. Put workflows in the instance ----------
WF="$COMFYUI_DIR/user/default/workflows"
mkdir -p "$WF"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp -f "$SCRIPT_DIR/workflows/qwen_rapid_aio_v18_diffusers.json" "$WF/qwen_rapid_aio_v18_diffusers.json"

python3 - <<'PY'
from importlib.metadata import distribution
from pathlib import Path
import shutil
names={'video_minimax_h3_i2v.json'}
d=distribution('comfyui-workflow-templates')
for f in d.files or []:
    p=Path(d.locate_file(f))
    if p.name in names and p.is_file():
        out=Path('/workspace/ComfyUI/user/default/workflows/video_minimax_h3_i2v_official.json')
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p,out)
        print('[OK] copied official H3 workflow from workflow-templates 0.11.57:', p)
        break
else:
    raise SystemExit('official video_minimax_h3_i2v.json not found in workflow-templates 0.11.57')
PY

# Patch the official H3 subgraph to chain the two user-selected H3 LoRAs.
H3_LORA1_STRENGTH="${H3_LORA1_STRENGTH:-0.8}" H3_LORA2_STRENGTH="${H3_LORA2_STRENGTH:-0.8}" python3 "$SCRIPT_DIR/patch_h3_workflow.py" \
  "$WF/video_minimax_h3_i2v_official.json" \
  "$WF/video_minimax_h3_i2v_web_loras.json"

# Apply the <=~1K business resolution default to the patched workflow.
python3 - <<'PY'
import json
from pathlib import Path
p=Path('/workspace/ComfyUI/user/default/workflows/video_minimax_h3_i2v_web_loras.json')
d=json.loads(p.read_text())
# ResolutionSelector widget order is [aspect_ratio, megapixels, multiple].
for n in d.get('nodes',[]):
    if n.get('type')=='ResolutionSelector':
        w=n.get('widgets_values')
        if isinstance(w,list) and len(w)>=2:
            w[1]=0.5
        wn=n.get('widgets_values_named',{})
        if isinstance(wn,dict): wn['megapixels']=0.5
# Also update any internal ResolutionSelector node if the current template stores it in a subgraph.
for sg in d.get('definitions',{}).get('subgraphs',[]):
    for n in sg.get('nodes',[]) or []:
        if n.get('type')=='ResolutionSelector':
            w=n.get('widgets_values')
            if isinstance(w,list) and len(w)>=2: w[1]=0.5
            wn=n.get('widgets_values_named',{})
            if isinstance(wn,dict): wn['megapixels']=0.5
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('[OK] H3 workflow default megapixels set to 0.5 (~1K-class max business target)')
PY

# ---------- 6. Launcher ----------
cat > "$WORKSPACE/run_comfyui.sh" <<LAUNCH
#!/usr/bin/env bash
set -euo pipefail
export QWEN_RAPID_VENV_PY="$QWEN_VENV/bin/python"
export QWEN_RAPID_BASE_DIR="$QWEN_BASE"
export QWEN_RAPID_TRANSFORMER_DIR="$QWEN_RAPID/transformer"
export QWEN_RAPID_RUNTIME_DIR="$WORKSPACE/qwen_rapid_runtime"
export QWEN_RAPID_PORT=18189
cd "$COMFYUI_DIR"
if (echo >/dev/tcp/127.0.0.1/$PORT) >/dev/null 2>&1; then
  echo "ComfyUI is already listening on $PORT. Use the existing Vast.ai ComfyUI service."
  exit 0
fi
exec python3 main.py --listen 0.0.0.0 --port $PORT --disable-api-nodes "\$@"
LAUNCH
chmod +x "$WORKSPACE/run_comfyui.sh"

# ---------- 7. Final check ----------
python3 "$SCRIPT_DIR/verify_models_and_workflows.py"

log "部署完成。"
log "Vast.ai ComfyUI 默认端口：$PORT"
log "工作流："
log "  $WF/qwen_rapid_aio_v18_diffusers.json"
log "  $WF/video_minimax_h3_i2v_web_loras.json"
log "启动（若 Vast 镜像没有自动启动服务）：bash $WORKSPACE/run_comfyui.sh"
