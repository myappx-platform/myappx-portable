#!/usr/bin/env python3
"""Assemble workspace/sources (Java pack) or workspace/kb (markdown corpus).

Owned by myappx-portable. Reads sibling git trees as data; does not live in plugins.

  py assemble.py sources --server-root ... --plugins-root ... --output ... [--clean]
  py assemble.py kb --plugins-root ... --kb-output ... [--docs-root ...]

Portable wrappers: bin\\assemble\\assemble-sources.bat and assemble-kb.bat
(use runtime\\python\\python.exe from PYTHON_ZIP, not system py)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

SKIP_DIR_NAMES = {
    "target",
    "bin",
    ".git",
    ".settings",
    ".idea",
    "node_modules",
    "classes",
    "work",
}

COPY_META = ("OSGI-INF", "META-INF", "plugin.xml", "build.properties")
FALLBACK_SOURCE_DIRS = ("src", "WEB-INF/src")
README_NAMES = ("README.md", "README.en.md", "readme.md", "readme.en.md")
GITKEEP = ".gitkeep"
FRONT_MATTER = re.compile(r"\A---\r?\n.*?\r?\n---\r?\n", re.DOTALL)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    src = sub.add_parser("sources", help="Assemble Java source pack")
    src.add_argument("--server-root", type=Path, required=True)
    src.add_argument("--plugins-root", type=Path, required=True)
    src.add_argument("--output", type=Path, required=True)
    src.add_argument(
        "--modules-file",
        type=Path,
        default=Path(__file__).with_name("source-modules.txt"),
    )
    src.add_argument("--clean", action="store_true", help="Delete --output first")

    kb = sub.add_parser("kb", help="Assemble markdown KB corpus")
    kb.add_argument("--plugins-root", type=Path, required=True)
    kb.add_argument("--kb-output", type=Path, required=True)
    kb.add_argument("--docs-root", type=Path, help="Optional id-docs checkout")
    return p.parse_args()


def load_modules(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    if not path.is_file():
        raise SystemExit(f"Modules file not found: {path}")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("plugins:"):
            rows.append(("plugins", line[len("plugins:") :].strip()))
        else:
            rows.append(("server", line))
    return rows


def read_source_dirs(module: Path) -> list[str]:
    bp = module / "build.properties"
    if not bp.is_file():
        return []
    text = bp.read_text(encoding="utf-8", errors="replace")
    joined = re.sub(r"\\\r?\n[ \t]*", "", text)
    dirs: list[str] = []
    for line in joined.splitlines():
        stripped = line.strip()
        if not stripped.startswith("source.."):
            continue
        _, _, rest = stripped.partition("=")
        for part in rest.split(","):
            rel = part.strip().replace("\\", "/").rstrip("/")
            if rel and rel not in dirs:
                dirs.append(rel)
    return dirs


def ensure_gitkeep(path: Path) -> None:
    keep = path / GITKEEP
    if not keep.exists():
        keep.write_bytes(b"")


def empty_generated_dir(path: Path) -> None:
    """Wipe generated files but keep the tracked placeholder so git still sees the directory."""
    path.mkdir(parents=True, exist_ok=True)
    for child in list(path.iterdir()):
        if child.name == GITKEEP:
            continue
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink(missing_ok=True)
    ensure_gitkeep(path)


def count_java(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(1 for _ in path.rglob("*.java"))


def _ignore(directory: str, names: list[str]) -> set[str]:
    return {n for n in names if n.lower() in SKIP_DIR_NAMES}


def copy_module(src: Path, dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    source_dirs = read_source_dirs(src)
    if not source_dirs:
        source_dirs = [d for d in FALLBACK_SOURCE_DIRS if (src / d).exists()]

    copied = False
    for rel in source_dirs:
        item = src / rel
        if not item.exists():
            print(f"  skip missing source dir: {rel}")
            continue
        target = dest / rel
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True, ignore=_ignore)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, target)
        copied = True

    for name in COPY_META:
        item = src / name
        if not item.exists():
            continue
        target = dest / name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True, ignore=_ignore)
        else:
            shutil.copy2(item, target)
        copied = True

    if not copied:
        shutil.copytree(src, dest, dirs_exist_ok=True, ignore=_ignore)

    java_n = count_java(dest)
    if java_n == 0:
        print(
            f"WARNING: {src.name} has 0 .java files after copy "
            f"(source..={source_dirs or 'none'})"
        )
    return java_n


def strip_front_matter(text: str) -> str:
    m = FRONT_MATTER.match(text)
    if not m:
        return text
    return text[m.end() :].lstrip("\n")


def os_walk_skip(root: Path):
    skip = {n.lower() for n in SKIP_DIR_NAMES}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d.lower() not in skip]
        yield dirpath, dirnames, filenames


def copy_markdown_tree(src_docs: Path, dest: Path) -> int:
    if not src_docs.is_dir():
        return 0
    n = 0
    for dirpath, _, filenames in os_walk_skip(src_docs):
        for name in filenames:
            if Path(name).suffix.lower() not in (".md", ".markdown"):
                continue
            md = Path(dirpath) / name
            dest_file = dest / md.relative_to(src_docs)
            dest_file.parent.mkdir(parents=True, exist_ok=True)
            text = md.read_text(encoding="utf-8", errors="replace")
            dest_file.write_text(strip_front_matter(text), encoding="utf-8")
            n += 1
    return n


# Sibling id-docs checkouts → assembled/docs/{key}. Markdown only (no Java/assets/HTML).
ID_DOC_TREES: tuple[tuple[str, str, str], ...] = (
    ("idempiere-rest-docs/docs", "docs/rest", "rest"),
    ("idempiere.github.io/docs", "docs/site", "site"),
    ("idempiere-skills", "docs/skills", "skills"),
)


def copy_id_docs(docs_root: Path | None, assembled: Path) -> dict[str, int]:
    counts = {key: 0 for _, _, key in ID_DOC_TREES}
    if docs_root is None:
        print("kb docs: skipped (no --docs-root)")
        return counts
    root = docs_root.resolve()
    if not root.is_dir():
        print(f"kb docs: skipped (not a directory): {root}")
        return counts

    for src_rel, dest_rel, key in ID_DOC_TREES:
        src = root.joinpath(*src_rel.split("/"))
        dest = assembled.joinpath(*dest_rel.split("/"))
        n = copy_markdown_tree(src, dest)
        if key == "rest":
            rest_readme = root / "idempiere-rest-docs" / "README.md"
            if rest_readme.is_file():
                dest.mkdir(parents=True, exist_ok=True)
                dest.joinpath("README.md").write_text(
                    strip_front_matter(
                        rest_readme.read_text(encoding="utf-8", errors="replace")
                    ),
                    encoding="utf-8",
                )
                n += 1
        counts[key] = n
        if n:
            print(f"copied id-docs {key} -> assembled/{dest_rel} ({n} md)")
        else:
            print(f"kb docs {key}: skipped (no markdown under {src})")
    return counts


def _iter_readmes(root: Path):
    for dirpath, dirnames, filenames in os_walk_skip(root):
        names = {n.lower(): n for n in filenames}
        for wanted in README_NAMES:
            actual = names.get(wanted.lower())
            if actual:
                yield Path(dirpath) / actual


def copy_kb_corpus(plugins_root: Path, kb_output: Path, docs_root: Path | None = None) -> dict:
    kb_output.mkdir(parents=True, exist_ok=True)
    assembled = kb_output / "assembled"
    drop = kb_output / "drop"
    drop.mkdir(parents=True, exist_ok=True)
    empty_generated_dir(assembled)
    (assembled / "plugins").mkdir(exist_ok=True)
    (assembled / "product").mkdir(exist_ok=True)

    readme_n = 0
    if plugins_root.is_dir():
        for readme in _iter_readmes(plugins_root):
            rel = readme.relative_to(plugins_root).as_posix()
            dest = assembled / "plugins" / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(readme, dest)
            readme_n += 1
            print(f"kb readme {rel}")

    docs_n = copy_id_docs(docs_root, assembled)

    skills_n = docs_n.get("skills", 0)
    rest_n = docs_n.get("rest", 0)
    site_n = docs_n.get("site", 0)
    manifest = {
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "assembledReadmes": readme_n,
        "skillsMarkdown": skills_n,
        "docsRestMarkdown": rest_n,
        "docsSiteMarkdown": site_n,
        "dropFiles": [p.name for p in drop.iterdir() if p.is_file()],
    }
    (kb_output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(
        f"wrote {kb_output / 'manifest.json'} "
        f"(readmes={readme_n}, skills={skills_n}, docsRest={rest_n}, docsSite={site_n})"
    )
    return manifest


def read_bundle_identity(module_dir: Path) -> tuple[str, str]:
    mf = module_dir / "META-INF" / "MANIFEST.MF"
    if not mf.is_file():
        return module_dir.name, ""
    symbolic = ""
    version = ""
    text = mf.read_text(encoding="utf-8", errors="replace")
    joined = re.sub(r"\r?\n ", "", text)
    for line in joined.splitlines():
        if line.startswith("Bundle-SymbolicName:"):
            symbolic = line.split(":", 1)[1].strip()
            symbolic = symbolic.split(";", 1)[0].strip()
        elif line.startswith("Bundle-Version:"):
            version = line.split(":", 1)[1].strip()
    return symbolic or module_dir.name, version


def assemble_sources(args: argparse.Namespace) -> int:
    output: Path = args.output.resolve()
    if args.clean:
        empty_generated_dir(output)
    else:
        output.mkdir(parents=True, exist_ok=True)
        ensure_gitkeep(output)

    modules = load_modules(args.modules_file)
    bundles: dict[str, dict[str, str]] = {}
    copied = 0
    missing: list[str] = []

    for kind, rel in modules:
        root = args.server_root if kind == "server" else args.plugins_root
        if root is None:
            missing.append(f"{kind}:{rel} (no --{kind}-root)")
            continue
        src = (root / rel).resolve()
        if not src.is_dir():
            missing.append(str(src))
            continue
        dest_name = src.name
        dest = output / dest_name
        if dest.exists() and dest_name != rel.replace("\\", "/").split("/")[-1]:
            dest = output / rel.replace("/", "_").replace("\\", "_")
        java_n = copy_module(src, dest)
        symbolic, version = read_bundle_identity(dest if (dest / "META-INF").is_dir() else src)
        if not (dest / "META-INF" / "MANIFEST.MF").is_file() and (src / "META-INF" / "MANIFEST.MF").is_file():
            (dest / "META-INF").mkdir(parents=True, exist_ok=True)
            shutil.copy2(src / "META-INF" / "MANIFEST.MF", dest / "META-INF" / "MANIFEST.MF")
            symbolic, version = read_bundle_identity(dest)
        rel_out = dest.relative_to(output).as_posix()
        bundles[symbolic] = {"version": version, "path": rel_out, "javaFiles": java_n}
        copied += 1
        print(f"copied {kind}:{rel} -> {rel_out} ({symbolic} {version}, {java_n} java)")

    index = {
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "copied": copied,
        "missing": missing,
        "bundles": bundles,
    }
    (output / "index.json").write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output / 'index.json'} ({copied} modules, {len(missing)} missing)")
    return 0 if copied else 1


def main() -> int:
    args = parse_args()
    if args.cmd == "sources":
        return assemble_sources(args)
    copy_kb_corpus(args.plugins_root.resolve(), args.kb_output.resolve(), args.docs_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
