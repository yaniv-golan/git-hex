#!/usr/bin/env python3

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator


@dataclass(frozen=True)
class LinkOccurrence:
    source_file: Path
    line_number: int
    raw_target: str


_FENCE_RE = re.compile(r"^\s*(```|~~~)")
_INLINE_LINK_RE = re.compile(r"!\[[^\]]*]\(([^)]+)\)|\[[^\]]+]\(([^)]+)\)")
_REF_DEF_RE = re.compile(r"^\s*\[([^\]]+)]\s*:\s*(\S+)(?:\s+\"[^\"]*\")?\s*$")
_SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _git_tracked_markdown_files(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "*.md"],
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    paths: list[Path] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        paths.append(root / line)
    return paths


def _iter_markdown_lines_excluding_fences(text: str) -> Iterator[tuple[int, str]]:
    in_fence = False
    for line_number, line in enumerate(text.splitlines(), start=1):
        if _FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        yield line_number, line


def _parse_reference_definitions(lines: Iterable[tuple[int, str]]) -> dict[str, str]:
    refs: dict[str, str] = {}
    for _, line in lines:
        match = _REF_DEF_RE.match(line)
        if not match:
            continue
        key = match.group(1).strip().lower()
        target = match.group(2).strip()
        refs[key] = target
    return refs


def _iter_inline_link_targets(
    source_file: Path, lines: Iterable[tuple[int, str]]
) -> Iterator[LinkOccurrence]:
    for line_number, line in lines:
        for match in _INLINE_LINK_RE.finditer(line):
            target = match.group(1) or match.group(2) or ""
            target = target.strip()
            if not target:
                continue
            yield LinkOccurrence(source_file=source_file, line_number=line_number, raw_target=target)


def _iter_reference_link_targets(
    source_file: Path, lines: Iterable[tuple[int, str]], refs: dict[str, str]
) -> Iterator[LinkOccurrence]:
    ref_link_re = re.compile(r"(?<!\!)\[[^\]]+]\[([^\]]*)]")
    for line_number, line in lines:
        for match in ref_link_re.finditer(line):
            key = (match.group(1) or "").strip().lower()
            if not key:
                continue
            target = refs.get(key)
            if not target:
                continue
            yield LinkOccurrence(source_file=source_file, line_number=line_number, raw_target=target)


def _normalize_target(raw: str) -> str:
    raw = raw.strip()
    if raw.startswith("<") and raw.endswith(">"):
        raw = raw[1:-1].strip()
    return raw


def _split_target(raw: str) -> str:
    raw = raw.split("#", 1)[0]
    raw = raw.split("?", 1)[0]
    return raw.strip()


def _is_local_path_target(raw: str) -> bool:
    if not raw or raw.startswith("#"):
        return False
    if _SCHEME_RE.match(raw):
        return False
    if raw.startswith("//"):
        return False
    return True


def _resolve_target_path(root: Path, source_file: Path, target: str) -> Path:
    if target.startswith("/"):
        return (root / target.lstrip("/")).resolve()
    return (source_file.parent / target).resolve()


def main() -> int:
    root = _repo_root()
    markdown_files = _git_tracked_markdown_files(root)

    missing: list[tuple[LinkOccurrence, Path]] = []

    for md_file in markdown_files:
        try:
            text = md_file.read_text(encoding="utf-8")
        except FileNotFoundError:
            continue

        filtered_lines = list(_iter_markdown_lines_excluding_fences(text))
        refs = _parse_reference_definitions(filtered_lines)

        occurrences = list(_iter_inline_link_targets(md_file, filtered_lines))
        occurrences.extend(_iter_reference_link_targets(md_file, filtered_lines, refs))

        for occ in occurrences:
            raw = _normalize_target(occ.raw_target)
            raw = _split_target(raw)
            if not _is_local_path_target(raw):
                continue

            resolved = _resolve_target_path(root, md_file, raw)
            try:
                resolved.relative_to(root.resolve())
            except ValueError:
                continue

            if not resolved.exists():
                missing.append((occ, resolved))

    if not missing:
        return 0

    print("Broken local Markdown links found:", file=sys.stderr)
    for occ, resolved in missing:
        rel_source = occ.source_file.relative_to(root)
        rel_target = str(resolved.relative_to(root))
        print(
            f"- {rel_source}:{occ.line_number}: {occ.raw_target} -> {rel_target} (missing)",
            file=sys.stderr,
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

