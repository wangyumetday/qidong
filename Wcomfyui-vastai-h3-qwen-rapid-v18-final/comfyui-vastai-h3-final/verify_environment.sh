#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR="${COMFYUI_DIR:-$WORKSPACE/ComfyUI}"
fail(){ echo "[FAIL] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }
[[ -d "$COMFYUI_DIR" ]] || fail "ComfyUI not found at $COMFYUI_DIR"
command -v python3 >/dev/null || fail "python3 missing"
command -v nvidia-smi >/dev/null || fail "nvidia-smi missing"
python3 - <<'PY' || fail "Python/PyTorch baseline mismatch"
import sys
assert sys.version_info[:2] == (3,12), sys.version_info
import torch
assert torch.__version__.split('+')[0] == '2.10.0', torch.__version__
assert torch.version.cuda == '13.0', torch.version.cuda
assert torch.cuda.is_available(), 'CUDA unavailable'
print('[OK] Python', sys.version.split()[0], '/ torch', torch.__version__, '/ cu130 / CUDA available')
PY
DRV=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d ' ')
python3 - "$DRV" <<'PY'
import sys
parts=tuple(int(x) for x in sys.argv[1].split('.')[:3])
assert parts >= (595,45,4), parts
print('[OK] NVIDIA driver >= 595.45.04:', sys.argv[1])
PY
VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1 | tr -d ' ')
if (( VRAM < 46000 )); then echo "[WARN] GPU VRAM ${VRAM} MiB; recommended baseline is 48GB."; else ok "GPU VRAM ${VRAM} MiB"; fi
python3 - <<'PY'
import importlib.metadata as m
want='0.11.57'
try: got=m.version('comfyui-workflow-templates')
except Exception as e: raise SystemExit(f'workflow templates missing: {e}')
assert got == want, got
print('[OK] workflow templates:', got)
PY

QWEN_VENV="${QWEN_RAPID_VENV:-$WORKSPACE/qwen_rapid_venv}"
QWEN_ROOT="${QWEN_RAPID_ROOT:-$WORKSPACE/qwen_rapid_models}"
if [[ -x "$QWEN_VENV/bin/python" ]]; then
  "$QWEN_VENV/bin/python" - <<'PY'
import diffusers, transformers
from diffusers import QwenImageEditPlusPipeline, QwenImageTransformer2DModel
assert diffusers.__version__ == "0.40.0", diffusers.__version__
assert transformers.__version__ == "5.3.0", transformers.__version__
print("[OK] Qwen Rapid venv: diffusers 0.40.0 / transformers 5.3.0")
PY
else
  echo "[WARN] Qwen Rapid venv not created yet: $QWEN_VENV"
fi
if [[ -f "$QWEN_ROOT/qwen_rapid_aio_v18/transformer/config.json" && -f "$QWEN_ROOT/qwen_image_edit_2511/model_index.json" ]]; then
  ok "Qwen Rapid model directories present"
else
  echo "[WARN] Qwen Rapid model directories not downloaded yet"
fi
