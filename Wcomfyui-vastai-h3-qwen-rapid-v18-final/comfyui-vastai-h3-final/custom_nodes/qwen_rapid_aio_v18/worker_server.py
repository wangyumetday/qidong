import json
import os
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import torch
from PIL import Image
from diffusers import QwenImageEditPlusPipeline, QwenImageTransformer2DModel

BASE_DIR = Path(os.environ.get("QWEN_RAPID_BASE_DIR", "/workspace/qwen_rapid_models/qwen_image_edit_2511"))
TRANSFORMER_DIR = Path(os.environ.get("QWEN_RAPID_TRANSFORMER_DIR", "/workspace/qwen_rapid_models/qwen_rapid_aio_v18/transformer"))
PORT = int(os.environ.get("QWEN_RAPID_PORT", "18189"))

PIPE = None


def load_pipe():
    global PIPE
    if PIPE is not None:
        return PIPE
    if not BASE_DIR.exists():
        raise RuntimeError(f"Base Qwen-Image-Edit-2511 directory missing: {BASE_DIR}")
    if not (TRANSFORMER_DIR / "config.json").exists():
        raise RuntimeError(f"Rapid transformer directory missing/config absent: {TRANSFORMER_DIR}")

    transformer = QwenImageTransformer2DModel.from_pretrained(
        str(TRANSFORMER_DIR),
        torch_dtype=torch.bfloat16,
        low_cpu_mem_usage=True,
    )
    pipe = QwenImageEditPlusPipeline.from_pretrained(
        str(BASE_DIR),
        transformer=transformer,
        torch_dtype=torch.bfloat16,
        low_cpu_mem_usage=True,
    )
    # 48GB-class deployment: keep idle components on host RAM.
    pipe.enable_model_cpu_offload()
    pipe.set_progress_bar_config(disable=True)
    PIPE = pipe
    return PIPE


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True, "loaded": PIPE is not None})
        else:
            self._json(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        if self.path != "/edit":
            self._json(404, {"ok": False, "error": "not found"})
            return
        try:
            n = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(n).decode("utf-8"))
            paths = payload.get("images") or []
            if not paths:
                raise ValueError("At least one input image is required.")
            images = [Image.open(p).convert("RGB") for p in paths]
            pipe = load_pipe()

            steps = int(payload.get("steps", 4))
            true_cfg = float(payload.get("true_cfg_scale", 1.0))
            seed = int(payload.get("seed", 0))
            generator = torch.Generator(device="cpu").manual_seed(seed)

            # Rapid AIO v18 is a 4-step distilled merge. The source project
            # recommends euler_ancestral/beta in native ComfyUI. Diffusers
            # does not expose a 1:1 KSampler euler_a/beta path, so we use the
            # pipeline's supported FlowMatch scheduler with 4 steps.
            out = pipe(
                prompt=str(payload.get("prompt", "")),
                image=images,
                negative_prompt=" ",
                true_cfg_scale=true_cfg,
                guidance_scale=1.0,
                num_inference_steps=steps,
                num_images_per_prompt=1,
                generator=generator,
            ).images[0]

            output = Path(payload["output"])
            output.parent.mkdir(parents=True, exist_ok=True)
            out.save(output)
            self._json(200, {"ok": True, "output": str(output)})
        except Exception as e:
            traceback.print_exc()
            self._json(500, {"ok": False, "error": f"{type(e).__name__}: {e}"})

    def log_message(self, fmt, *args):
        print("[QWEN-RAPID]", fmt % args, flush=True)


if __name__ == "__main__":
    print(f"[QWEN-RAPID] worker starting on 127.0.0.1:{PORT}", flush=True)
    print(f"[QWEN-RAPID] base={BASE_DIR}", flush=True)
    print(f"[QWEN-RAPID] transformer={TRANSFORMER_DIR}", flush=True)
    load_pipe()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
