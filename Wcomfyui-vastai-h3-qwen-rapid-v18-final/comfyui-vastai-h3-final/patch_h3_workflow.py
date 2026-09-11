#!/usr/bin/env python3
"""Patch official ComfyUI MiniMax H3 I2V template with two web-matched H3 LoRAs.

The official H3 template stores the H3 sampler path inside a subgraph. This patcher
finds the first UNETLoader inside the subgraph, inserts two native LoraLoaderModelOnly
nodes, and reconnects MODEL -> LoRA1 -> LoRA2 -> original downstream target.
It refuses to write a patched workflow if the graph shape is unexpected.
"""
from __future__ import annotations
import json, pathlib, sys

LORA1 = "H3_Motion_BoosterV2.safetensors"
LORA2 = "MysticXXX_MMH3-V4.safetensors"
import os
STRENGTH1 = float(os.environ.get("H3_LORA1_STRENGTH", "0.8"))
STRENGTH2 = float(os.environ.get("H3_LORA2_STRENGTH", "0.8"))


def all_node_lists(doc: dict):
    root = doc.get("nodes")
    if isinstance(root, list):
        yield root, doc
    defs = doc.get("definitions", {})
    for sg in defs.get("subgraphs", []) if isinstance(defs, dict) else []:
        nodes = sg.get("nodes")
        if isinstance(nodes, list):
            yield nodes, sg


def max_id(nodes, key):
    return max((int(n.get(key, 0)) for n in nodes if isinstance(n, dict) and str(n.get(key, "")).lstrip("-").isdigit()), default=0)


def find_lora_count(nodes):
    return sum(1 for n in nodes if isinstance(n, dict) and n.get("type") == "LoraLoaderModelOnly")


def patch_subgraph(nodes):
    unets = [n for n in nodes if n.get("type") == "UNETLoader"]
    if len(unets) != 1:
        return False, f"expected exactly 1 UNETLoader in subgraph, found {len(unets)}"
    unet = unets[0]
    if not unet.get("outputs") or not unet["outputs"][0].get("links"):
        return False, "UNETLoader output 0 has no links"
    old_link_id = unet["outputs"][0]["links"][0]
    links = None
    # links live alongside the subgraph node list in the containing object; handled by caller.
    return True, (unet, old_link_id)


def main(src: pathlib.Path, dst: pathlib.Path) -> int:
    data = json.loads(src.read_text(encoding="utf-8"))
    defs = data.get("definitions", {})
    subgraphs = defs.get("subgraphs", []) if isinstance(defs, dict) else []
    if not subgraphs:
        print("ERROR: official H3 template has no subgraphs; refusing to guess.", file=sys.stderr)
        return 2

    target = None
    for sg in subgraphs:
        nodes = sg.get("nodes")
        if not isinstance(nodes, list):
            continue
        if any(n.get("type") == "UNETLoader" for n in nodes):
            if target is not None:
                print("ERROR: multiple subgraphs contain UNETLoader; refusing to guess.", file=sys.stderr)
                return 2
            target = sg

    if target is None:
        print("ERROR: no H3 subgraph with UNETLoader found.", file=sys.stderr)
        return 2

    nodes = target["nodes"]
    links = target.get("links")
    if not isinstance(links, list):
        print("ERROR: target subgraph has no link list.", file=sys.stderr)
        return 2

    unet = next(n for n in nodes if n.get("type") == "UNETLoader")
    out0 = unet.get("outputs", [{}])[0]
    out_links = out0.get("links") or []
    if len(out_links) != 1:
        print(f"ERROR: UNETLoader output has {len(out_links)} outgoing links; refusing to guess.", file=sys.stderr)
        return 2
    old_link_id = out_links[0]

    link_row = next((row for row in links if row and row[0] == old_link_id), None)
    if not link_row or len(link_row) < 6:
        print(f"ERROR: link {old_link_id} not found or malformed.", file=sys.stderr)
        return 2
    _, _, src_slot, target_node_id, target_slot, link_type = link_row[:6]
    target_node = next((n for n in nodes if n.get("id") == target_node_id), None)
    if target_node is None:
        print("ERROR: original link target node not found.", file=sys.stderr)
        return 2
    if target_slot >= len(target_node.get("inputs", [])):
        print("ERROR: original target slot out of range.", file=sys.stderr)
        return 2

    # Ensure we do not double-patch.
    if find_lora_count(nodes) >= 2:
        print("Workflow already contains at least 2 LoraLoaderModelOnly nodes; copying unchanged.")
        dst.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return 0

    max_node = max_id(nodes, "id")
    max_link = max((int(r[0]) for r in links if r and str(r[0]).isdigit()), default=0)
    l1_id, l2_id = max_node + 1, max_node + 2
    l1_link, l2_link = max_link + 1, max_link + 2

    base_pos = unet.get("pos", [0, 0])
    x, y = (base_pos + [0, 0])[:2]
    common = {
        "flags": {}, "mode": 0,
        "inputs": [{"name": "model", "type": "MODEL", "link": None}],
        "outputs": [{"name": "MODEL", "type": "MODEL", "links": []}],
        "properties": {"cnr_id": "comfy-core", "ver": "0.35.0", "Node name for S&R": "LoraLoaderModelOnly"},
        "size": [315, 82],
        "widgets_values_named": {}
    }
    l1 = dict(common)
    l1.update({"id": l1_id, "type": "LoraLoaderModelOnly", "pos": [x + 360, y],
               "title": "H3 Motion Booster V0.2", "widgets_values": [LORA1, STRENGTH1],
               "widgets_values_named": {"lora_name": LORA1, "strength_model": STRENGTH1}})
    l2 = dict(common)
    l2.update({"id": l2_id, "type": "LoraLoaderModelOnly", "pos": [x + 720, y],
               "title": "Mystic XXX V4", "widgets_values": [LORA2, STRENGTH2],
               "widgets_values_named": {"lora_name": LORA2, "strength_model": STRENGTH2}})

    # Re-purpose old UNET -> downstream link as UNET -> LoRA1.
    link_row[3] = l1_id
    link_row[4] = 0
    # Downstream node input now receives lora2 output.
    target_node["inputs"][target_slot]["link"] = l2_link

    l1["inputs"][0]["link"] = old_link_id
    l1["outputs"][0]["links"] = [l1_link]
    l2["inputs"][0]["link"] = l1_link
    l2["outputs"][0]["links"] = [l2_link]
    links.append([l1_link, l1_id, 0, l2_id, 0, "MODEL"])
    links.append([l2_link, l2_id, 0, target_node_id, target_slot, link_type])

    # Remove old link id from UNET output and re-add it unchanged as its output->LoRA1 link.
    unet["outputs"][0]["links"] = [old_link_id]

    nodes.extend([l1, l2])
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Patched H3 workflow with {LORA1} ({STRENGTH1}) -> {LORA2} ({STRENGTH2}).")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: patch_h3_workflow.py SOURCE_JSON DEST_JSON", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])))
