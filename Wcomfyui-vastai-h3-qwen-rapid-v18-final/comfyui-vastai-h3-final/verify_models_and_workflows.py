#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, os, sys
from pathlib import Path

ROOT=Path(os.environ.get("COMFYUI_DIR","/workspace/ComfyUI"))
checks={
 'diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors':'e889202c41dafb67b10d67b97f0d8541508036a6090af23425a5c2615d03c47a',
 'text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors':'35a88d51044231fe332301d7a62aa81e3f2cba62febeb446e2c1e3e0ef76f2c6',
 'vae/minimax_h3_video_vae_fp16.safetensors':'7c1f131492e7eddacaac9069a61b81bdd39de5cc96561e677c5eab1cdce5e522',
 'vae/minimax_h3_audio_vae_fp32.safetensors':'8e505d95dd1561d47abd43d4238fd40d9bb1ae9e147ed0a4cba778d76ae4db48',
 'loras/H3_Motion_BoosterV2.safetensors':'f6a6897162b921d2b74abe1fdebcd80c8189147e70e0e0738200756c250336c3',
 'loras/MysticXXX_MMH3-V4.safetensors':'fc3e856d14c6c19557c888f48662d591e4794e281233ec0d987be5003068afba',
}
for rel, exp in checks.items():
    p=ROOT/'models'/rel
    if not p.is_file(): raise SystemExit(f'MISSING: {p}')
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(8*1024*1024), b''): h.update(b)
    got=h.hexdigest()
    if got!=exp: raise SystemExit(f'HASH FAIL {rel}: {got} != {exp}')
print('[OK] H3 model SHA256 checks passed')

wf=ROOT/'user/default/workflows/video_minimax_h3_i2v_web_loras.json'
d=json.loads(wf.read_text(encoding='utf-8'))
allnodes=list(d.get('nodes',[]))
for sg in d.get('definitions',{}).get('subgraphs',[]): allnodes.extend(sg.get('nodes',[]) or [])
loras=[n for n in allnodes if n.get('type')=='LoraLoaderModelOnly']
names=[(n.get('widgets_values') or [''])[0] for n in loras]
for required in ('H3_Motion_BoosterV2.safetensors','MysticXXX_MMH3-V4.safetensors'):
    if required not in names: raise SystemExit(f'workflow missing {required}')
print('[OK] patched H3 workflow contains both web-matched H3 LoRAs')

qwf=ROOT/'user/default/workflows/qwen_rapid_aio_v18_diffusers.json'
qd=json.loads(qwf.read_text(encoding='utf-8'))
types={n.get('type') for n in qd.get('nodes',[])}
if 'QwenRapidAIOV18Edit' not in types:
    raise SystemExit('Qwen Rapid workflow missing QwenRapidAIOV18Edit node')
print('[OK] Qwen Rapid v18 workflow graph references bundled custom node')

qroot=Path(os.environ.get('QWEN_RAPID_ROOT','/workspace/qwen_rapid_models'))
base=qroot/'qwen_image_edit_2511'
rapid=qroot/'qwen_rapid_aio_v18'
for p in [
    base/'model_index.json',
    base/'vae/config.json',
    base/'text_encoder/config.json',
    base/'processor/preprocessor_config.json',
    rapid/'transformer/config.json',
]:
    if not p.exists(): raise SystemExit(f'MISSING Qwen Rapid runtime asset: {p}')
print('[OK] Qwen Rapid base/transformer static assets present')
