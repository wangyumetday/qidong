import base64
import json
import os
import subprocess
import time
import uuid
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError

import numpy as np
from PIL import Image
import torch


NODE_ROOT = Path(__file__).resolve().parent
WORKER = NODE_ROOT / "worker_server.py"
VENV_PY = Path(os.environ.get("QWEN_RAPID_VENV_PY", "/workspace/qwen_rapid_venv/bin/python"))
PORT = int(os.environ.get("QWEN_RAPID_PORT", "18189"))
BASE_DIR = Path(os.environ.get("QWEN_RAPID_BASE_DIR", "/workspace/qwen_rapid_models/qwen_image_edit_2511"))
TRANSFORMER_DIR = Path(os.environ.get("QWEN_RAPID_TRANSFORMER_DIR", "/workspace/qwen_rapid_models/qwen_rapid_aio_v18/transformer"))
RUNTIME_DIR = Path(os.environ.get("QWEN_RAPID_RUNTIME_DIR", "/workspace/qwen_rapid_runtime"))
RUNTIME_DIR.mkdir(parents=True, exist_ok=True)


def _health():
    try:
        with urlopen(f"http://127.0.0.1:{PORT}/health", timeout=1.5) as r:
            return r.read().decode("utf-8")
    except Exception:
        return None


def _ensure_server():
    if _health():
        return
    if not VENV_PY.exists():
        raise RuntimeError(
            f"Qwen Rapid runtime not found: {VENV_PY}. "
            "Run deploy_comfyui_vastai_h3.sh first."
        )
    log = open(RUNTIME_DIR / "worker.log", "a", buffering=1)
    env = os.environ.copy()
    env.update({
        "QWEN_RAPID_BASE_DIR": str(BASE_DIR),
        "QWEN_RAPID_TRANSFORMER_DIR": str(TRANSFORMER_DIR),
        "QWEN_RAPID_PORT": str(PORT),
    })
    subprocess.Popen(
        [str(VENV_PY), str(WORKER)],
        cwd=str(NODE_ROOT),
        env=env,
        stdout=log,
        stderr=log,
        start_new_session=True,
    )
    for _ in range(120):
        if _health():
            return
        time.sleep(0.5)
    raise RuntimeError(
        "Qwen Rapid worker did not become ready. "
        f"See {RUNTIME_DIR / 'worker.log'}"
    )


def _save_tensor_image(tensor, path):
    arr = tensor.detach().cpu().numpy()
    if arr.ndim == 4:
        arr = arr[0]
    arr = np.clip(arr * 255.0, 0, 255).astype(np.uint8)
    Image.fromarray(arr, mode="RGB").save(path)


def _load_tensor_image(path):
    img = Image.open(path).convert("RGB")
    arr = np.asarray(img).astype(np.float32) / 255.0
    return torch.from_numpy(arr)[None, ...]


class QwenRapidAIOV18Edit:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image1": ("IMAGE",),
                "prompt": ("STRING", {"multiline": True, "default": "Edit the image according to the instruction."}),
                "steps": ("INT", {"default": 4, "min": 4, "max": 8, "step": 1}),
                "true_cfg_scale": ("FLOAT", {"default": 1.0, "min": 1.0, "max": 6.0, "step": 0.1}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 0xffffffffffffffff}),
            },
            "optional": {
                "image2": ("IMAGE",),
                "image3": ("IMAGE",),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "edit"
    CATEGORY = "Qwen/Rapid-AIO-v18"
    DESCRIPTION = "Qwen Rapid AIO v18 NSFW Diffusers transformer, 4-step image editing."

    def edit(self, image1, prompt, steps=4, true_cfg_scale=1.0, seed=0, image2=None, image3=None):
        _ensure_server()

        job = uuid.uuid4().hex
        input_dir = RUNTIME_DIR / "inputs"
        output_dir = RUNTIME_DIR / "outputs"
        input_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)

        paths = []
        for idx, img in enumerate([image1, image2, image3], start=1):
            if img is None:
                continue
            p = input_dir / f"{job}_{idx}.png"
            _save_tensor_image(img, p)
            paths.append(str(p))

        payload = {
            "job_id": job,
            "images": paths,
            "prompt": prompt,
            "steps": int(steps),
            "true_cfg_scale": float(true_cfg_scale),
            "seed": int(seed),
            "output": str(output_dir / f"{job}.png"),
        }
        body = json.dumps(payload).encode("utf-8")
        req = Request(
            f"http://127.0.0.1:{PORT}/edit",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urlopen(req, timeout=3600) as r:
                result = json.loads(r.read().decode("utf-8"))
        except Exception as e:
            raise RuntimeError(f"Qwen Rapid worker request failed: {e}") from e

        if not result.get("ok"):
            raise RuntimeError(result.get("error", "Unknown Qwen Rapid worker error"))

        out = Path(result["output"])
        if not out.is_file():
            raise RuntimeError(f"Worker reported success but output is missing: {out}")
        return (_load_tensor_image(out),)


NODE_CLASS_MAPPINGS = {
    "QwenRapidAIOV18Edit": QwenRapidAIOV18Edit,
}
NODE_DISPLAY_NAME_MAPPINGS = {
    "QwenRapidAIOV18Edit": "Qwen Rapid AIO v18 NSFW (Diffusers)",
}
