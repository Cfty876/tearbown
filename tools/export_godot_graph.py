"""Add a GDScript index that Graphify can query without an LLM."""

from collections import defaultdict
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "teardown" / "идеальная версия"
GAME = SOURCE / "game"
OUT = ROOT / "graphify-out" / "breakpoint-godot.json"

DECLARATION = re.compile(r"^(class_name|func|static func|signal)\s+(\w+)")
REFERENCE = re.compile(r'(?P<path>res://[^"\x27\n]+?\.gd)\b|\b(?P<name>[A-Za-z_]\w*)\b')
STRING_OR_COMMENT = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|#.*')
ROLES = {
    "core": "Game state and networking",
    "player": "First-person player and tools",
    "ui": "Menus and HUD",
    "voxel": "Voxel simulation",
    "school": "School and NPCs",
    "world": "Maps and interactions",
}


def build():
    nodes = {}
    links = {}
    scripts = {}
    symbols = defaultdict(set)
    communities = {}
    for path in sorted((GAME / "scripts").rglob("*.gd")):
        relative = path.relative_to(GAME).as_posix()
        source_file = path.relative_to(ROOT).as_posix()
        role = "school" if "/school/" in relative else relative.split("/")[1].removesuffix(".gd")
        community = communities.setdefault(role, len(communities))
        lines = path.read_text(encoding="utf-8-sig").splitlines()
        declarations = [(i, *match.groups()) for i, line in enumerate(lines, 1)
                        if (match := DECLARATION.match(line))]
        autoload = next((name for name, target in autoloads.items() if target == relative), "")
        label = next((name for _, kind, name in declarations if kind == "class_name"),
                     autoload or path.stem)
        node_id = "gd:" + relative
        nodes[node_id] = dict(id=node_id, label=label, file_type="code",
                              source_file=source_file, source_location="L1",
                              community=community, community_name=ROLES.get(role, role))
        scripts[relative] = (node_id, lines, declarations)
        if label != path.stem or autoload:
            symbols[label].add(node_id)
        if autoload:
            symbols[autoload].add(node_id)
    for relative, (node_id, lines, declarations) in scripts.items():
        current = node_id
        declared = {line: (kind, name) for line, kind, name in declarations}
        for line_no, line in enumerate(lines, 1):
            if line_no in declared:
                kind, name = declared[line_no]
                if kind == "class_name":
                    continue
                current = f"{node_id}:{name}"
                nodes[current] = dict(nodes[node_id], id=current,
                                      label=f"{nodes[node_id]['label']}.{name}()" if kind != "signal"
                                      else f"{nodes[node_id]['label']}.{name}",
                                      source_location=f"L{line_no}")
                add_link(links, nodes, node_id, current, "declares", line_no, "EXTRACTED")
                continue
            if line and not line[0].isspace() and not line.startswith("#"):
                current = node_id
            for match in REFERENCE.finditer(STRING_OR_COMMENT.sub(
                    lambda part: part[0] if part[0].startswith(('\"res://', "'res://")) else "", line)):
                resource, name = match.groups()
                if resource and resource[6:] in scripts:
                    destination = {scripts[resource[6:]][0]}
                else:
                    destination = symbols[name] if name in symbols else set()
                if len(destination) == 1:
                    target = next(iter(destination))
                    if target != node_id:
                        add_link(links, nodes, current, target, "references", line_no,
                                 "EXTRACTED" if resource else "INFERRED")
    graph = dict(directed=True, multigraph=False, graph={"schema_version": 1},
                 nodes=list(nodes.values()), links=list(links.values()), hyperedges=[])
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(graph, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{len(scripts)} GDScript files, {len(nodes)} nodes, {len(links)} links in {OUT}")


def add_link(links, nodes, start, end, relation, line_no, confidence):
    links.setdefault((start, end), dict(
        source=start, target=end, relation=relation, weight=1,
        confidence=confidence, confidence_score=1 if confidence == "EXTRACTED" else 0.8,
        source_file=nodes[start]["source_file"], source_location=f"L{line_no}",
    ))


if __name__ == "__main__":
    project = (GAME / "project.godot").read_text(encoding="utf-8-sig")
    autoloads = dict(re.findall(r'^(\w+)="\*res://([^"]+\.gd)"', project, re.MULTILINE))
    build()
