#!/usr/bin/env bash
set -Eeuo pipefail

COMFYUI_DIR="${COMFYUI_DIR:-/workspace/ComfyUI}"
COMFYUI_REF="${COMFYUI_REF:-v0.3.26}"
STORYDIFFUSION_REF="${STORYDIFFUSION_REF:-v1}"
LLM_PARTY_REF="${LLM_PARTY_REF:-v0.5.0}"
OLLAMA_MODEL="${OLLAMA_MODEL:-my-story-writer}"
GGUF_DIR="${GGUF_DIR:-/workspace/llm}"
GGUF_FILE="${GGUF_FILE:-Qwen3-24B-A4B-Freedom-Think-Ablit-Heretic-Neo-D_AU-Q4_K_M-imat.gguf}"
CIVITAI_TOKEN="16a3599303fb00e52140356bb62df435"
GH_PROXY="${GH_PROXY:-}"
GITHUB_BASE="${GH_PROXY}https://github.com"
HF_ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"
ARIA_X="${ARIA_X:-16}"
ARIA_S="${ARIA_S:-16}"
RETRY="${RETRY:-8}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
LOG_DIR="${LOG_DIR:-/workspace/logs}"
mkdir -p "$LOG_DIR"
log(){ printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
warn(){ printf '\n[WARN] %s\n' "$*" >&2; }
die(){ printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
trap 'warn "部署失败，最后执行命令：${BASH_COMMAND}"' ERR

apt_install(){ apt-get update -y && apt-get install -y --no-install-recommends "$@"; }
ensure_tools(){
  command -v curl >/dev/null 2>&1 || apt_install curl
  command -v git >/dev/null 2>&1 || apt_install git
  command -v unzip >/dev/null 2>&1 || apt_install unzip
  command -v aria2c >/dev/null 2>&1 || apt_install aria2
  command -v rsync >/dev/null 2>&1 || apt_install rsync
  command -v pgrep >/dev/null 2>&1 || true
}

curl_resume(){
  local url="$1" dest="$2"; mkdir -p "$(dirname "$dest")"
  curl -fL --retry "$RETRY" --retry-all-errors --connect-timeout 20 --max-time 0 -C - -o "$dest" "$url"
}
aria_download(){
  local url="$1" dest="$2"; mkdir -p "$(dirname "$dest")"
  aria2c --continue=true --allow-overwrite=false --file-allocation=none \
    --max-connection-per-server="$ARIA_X" --split="$ARIA_S" --min-split-size=8M \
    --max-tries="$RETRY" --retry-wait=5 --timeout=30 --connect-timeout=20 \
    --lowest-speed-limit=512K --summary-interval=10 --console-log-level=notice \
    -d "$(dirname "$dest")" -o "$(basename "$dest")" "$url"
}
github_zip(){
  local repo="$1" ref="$2" dest="$3"; local zip="/tmp/$(basename "$repo")_${ref}.zip"; local tmp
  tmp="$(mktemp -d)"
  curl_resume "${GITHUB_BASE}/${repo}/archive/refs/tags/${ref}.zip" "$zip"
  unzip -q "$zip" -d "$tmp"
  local inner; inner="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$inner" ]] || die "GitHub ZIP 解压失败：$repo@$ref"
  rm -rf "$dest"; mkdir -p "$(dirname "$dest")"; mv "$inner" "$dest"; rm -rf "$tmp" "$zip"
}

setup_comfyui(){
  log "==== ComfyUI ${COMFYUI_REF} ===="; mkdir -p /workspace
  if [[ -d "$COMFYUI_DIR/.git" ]]; then
    git -C "$COMFYUI_DIR" remote set-url origin https://github.com/comfyanonymous/ComfyUI.git || true
    git -C "$COMFYUI_DIR" fetch --tags --depth 1 origin "$COMFYUI_REF"
    git -C "$COMFYUI_DIR" checkout -f "$COMFYUI_REF"
    git -C "$COMFYUI_DIR" clean -fd -e models -e input -e output -e custom_nodes || true
  else
    local backup="${COMFYUI_DIR}.before_locked_$(date +%Y%m%d_%H%M%S)"
    if [[ -d "$COMFYUI_DIR" ]]; then mv "$COMFYUI_DIR" "$backup"; fi
    git clone --depth 1 --branch "$COMFYUI_REF" https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
    if [[ -d "$backup/models" ]]; then rsync -a "$backup/models/" "$COMFYUI_DIR/models/"; fi
    if [[ -d "$backup/input" ]]; then rsync -a "$backup/input/" "$COMFYUI_DIR/input/"; fi
    if [[ -d "$backup/output" ]]; then rsync -a "$backup/output/" "$COMFYUI_DIR/output/"; fi
  fi
  cd "$COMFYUI_DIR"
  "$PYTHON_BIN" -m pip install -U pip setuptools wheel
  "$PYTHON_BIN" -m pip install --prefer-binary --no-cache-dir -r requirements.txt
  mkdir -p custom_nodes models/photomaker models/checkpoints input output
}
install_node(){
  local repo="$1" ref="$2" name="$3" dest="${COMFYUI_DIR}/custom_nodes/${3}"
  if [[ -d "$dest" && -d "$dest/.git" ]]; then
    git -C "$dest" fetch --tags --depth 1 origin "$ref" || true
    git -C "$dest" checkout -f "$ref"
  else
    [[ -d "$dest" ]] && mv "$dest" "${dest}.old_$(date +%s)"
    github_zip "$repo" "$ref" "$dest"
  fi
  if [[ -f "$dest/requirements.txt" ]]; then
    "$PYTHON_BIN" -m pip install --prefer-binary --no-cache-dir -r "$dest/requirements.txt" || warn "$name requirements 有告警，后续强制锁版本"
  fi
}
setup_nodes(){
  log "==== Custom Nodes（只装必要节点） ===="
  install_node "smthemex/ComfyUI_StoryDiffusion" "$STORYDIFFUSION_REF" "ComfyUI_StoryDiffusion"
  install_node "heshengtao/comfyui_LLM_party" "$LLM_PARTY_REF" "comfyui_LLM_party"
  "$PYTHON_BIN" -m pip install --prefer-binary --no-cache-dir \
    'diffusers==0.29.0' 'transformers==4.49.0' 'huggingface-hub==0.25.2' \
    'insightface==0.7.3' 'numpy<2' 'onnxruntime-gpu' peft omegaconf safetensors accelerate
}
setup_photomaker(){
  local dest="${COMFYUI_DIR}/models/photomaker/photomaker-v2.bin"
  [[ -f "$dest" ]] && { log "PhotoMaker V2 已存在"; return; }
  aria_download "${HF_ENDPOINT}/TencentARC/PhotoMaker-V2/resolve/main/photomaker-v2.bin?download=true" "$dest"
}
setup_wai(){
  local dest="${COMFYUI_DIR}/models/checkpoints/WAI-REAL_CN.safetensors"
  [[ -f "$dest" ]] && { log "WAI-REAL_CN 已存在"; return; }
  aria_download "https://civitai.com/api/download/models/2029578?token=${CIVITAI_TOKEN}" "$dest"
}
setup_ollama(){
  log "==== Ollama + Qwen3 GGUF ===="
  command -v ollama >/dev/null 2>&1 || curl -fsSL https://ollama.com/install.sh | sh
  if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    nohup env OLLAMA_HOST=127.0.0.1:11434 OLLAMA_KEEP_ALIVE=-1 ollama serve >"$LOG_DIR/ollama.log" 2>&1 &
    for _ in $(seq 1 30); do curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break; sleep 1; done
    curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 || die "Ollama 启动失败：$LOG_DIR/ollama.log"
  fi
  mkdir -p "$GGUF_DIR"; local gguf="${GGUF_DIR}/${GGUF_FILE}"
  if [[ ! -f "$gguf" ]]; then
    aria_download "${HF_ENDPOINT}/DavidAU/Qwen3-24B-A4B-Freedom-Thinking-Abliterated-Heretic-NEO-Imatrix-GGUF/resolve/main/${GGUF_FILE}?download=true" "$gguf"
  fi
  cat >/tmp/Modelfile.story <<EOF
FROM ${gguf}
PARAMETER temperature 0.8
PARAMETER num_ctx 8192
PARAMETER think false
EOF
  if ! ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$OLLAMA_MODEL"; then ollama create "$OLLAMA_MODEL" -f /tmp/Modelfile.story; fi
}
start_services(){
  if ! pgrep -f "python.*main.py.*--port 8188" >/dev/null 2>&1; then
    cd "$COMFYUI_DIR"
    nohup "$PYTHON_BIN" main.py --listen 0.0.0.0 --port 8188 >"$LOG_DIR/comfyui.log" 2>&1 & echo $! >"$LOG_DIR/comfyui.pid"
  fi
  for _ in $(seq 1 45); do curl -fsS http://127.0.0.1:8188/ >/dev/null 2>&1 && break; sleep 1; done
  curl -fsS http://127.0.0.1:8188/ >/dev/null 2>&1 && log "✅ ComfyUI 已启动" || warn "ComfyUI 尚未通过健康检查，查看 $LOG_DIR/comfyui.log"
}
main(){
  log "===== Vast.ai 一键部署开始 ====="; ensure_tools; setup_comfyui; setup_nodes; setup_photomaker; setup_wai; setup_ollama; start_services
  log "===== 全部完成 ====="
  echo "ComfyUI: http://127.0.0.1:8188"; echo "Ollama: http://127.0.0.1:11434"; echo "Logs: $LOG_DIR"
  echo "ComfyUI: $(git -C "$COMFYUI_DIR" describe --tags --always 2>/dev/null || true)"
  echo "StoryDiffusion: $(git -C "$COMFYUI_DIR/custom_nodes/ComfyUI_StoryDiffusion" describe --tags --always 2>/dev/null || true)"
  echo "LLM Party: $(git -C "$COMFYUI_DIR/custom_nodes/comfyui_LLM_party" describe --tags --always 2>/dev/null || true)"
  "$PYTHON_BIN" - <<'PYINNER'
mods=['diffusers','transformers','huggingface_hub','insightface','numpy','onnxruntime']
for n in mods:
    try:
        m=__import__(n); print(f'{n}: {getattr(m,"__version__","unknown")}')
    except Exception as e: print(f'{n}: IMPORT_ERROR {e}')
PYINNER
  ollama list || true
}
main "$@"
