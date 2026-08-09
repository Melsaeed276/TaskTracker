#!/usr/bin/env python3
"""Remove XcodeGen local-package folder refs from project.pbxproj.

XcodeGen always adds each local package as a blue PBXFileReference folder under
a Packages group, in addition to XCLocalSwiftPackageReference. SourceKit then
indexes Tests/ against the app project root and emits:

  Source files for target AppDataTests should be located under
  'Tests/AppDataTests', 'Tests', or a custom sources path...

This script drops only those folder refs and the empty Packages group. SPM
wiring (XCLocalSwiftPackageReference / product dependencies) is left intact.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    pbx = root / "TaskTracker.xcodeproj" / "project.pbxproj"
    text = pbx.read_text()

    folder_re = re.compile(
        r"^\t\t([A-F0-9]{24}) /\* .+ \*/ = "
        r"\{isa = PBXFileReference; lastKnownFileType = folder; "
        r"name = .+; path = Packages/.+; sourceTree = SOURCE_ROOT; \};\n",
        re.MULTILINE,
    )
    folder_ids = {m.group(1) for m in folder_re.finditer(text)}
    if not folder_ids:
        print("strip-local-package-folder-refs: nothing to strip")
        return 0

    text = folder_re.sub("", text)

    # Drop the Packages group XcodeGen creates for those folder refs.
    packages_group_re = re.compile(
        r"^\t\t([A-F0-9]{24}) /\* Packages \*/ = \{\n"
        r"\t\t\tisa = PBXGroup;\n"
        r"\t\t\tchildren = \(\n"
        r"(?:\t\t\t\t[A-F0-9]{24} /\* .+ \*/,\n)*"
        r"\t\t\t\);\n"
        r"\t\t\tpath = Packages;\n"
        r"\t\t\tsourceTree = \"<group>\";\n"
        r"\t\t\};\n",
        re.MULTILINE,
    )
    group_ids = {m.group(1) for m in packages_group_re.finditer(text)}
    text = packages_group_re.sub("", text)

    drop_ids = folder_ids | group_ids
    for oid in drop_ids:
        text = re.sub(
            rf"^\t\t\t\t{oid} /\* .+ \*/,\n",
            "",
            text,
            flags=re.MULTILINE,
        )

    pbx.write_text(text)
    print(
        "strip-local-package-folder-refs: removed "
        f"{len(folder_ids)} folder ref(s), {len(group_ids)} Packages group(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
