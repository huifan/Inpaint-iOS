#!/usr/bin/env python3
"""Add new Swift files to the Inpaint Xcode project."""

import hashlib
import re
import sys

PBXPROJ_PATH = "/Users/lee/Inpaint-iOS/Inpaint.xcodeproj/project.pbxproj"

# Files to add: (relative_path_from_Inpaint_dir, filename)
NEW_FILES = [
    "Core/Protocols/ImageProcessor.swift",
    "Core/Protocols/MaskBasedProcessor.swift",
    "Core/Models/ProcessingResult.swift",
    "Core/Models/ToolDefinition.swift",
    "Core/Models/ProcessingOptions.swift",
    "Core/Services/ToolRegistry.swift",
    "Core/Services/ExportService.swift",
    "Core/Services/ImagePickerService.swift",
    "Core/Services/EditHistoryService.swift",
    "Core/Views/ProcessingOverlay.swift",
    "Core/Views/BaseEditingViewController.swift",
    "Features/Home/HomeViewController.swift",
    "Features/Home/ToolCell.swift",
    "Features/Inpainting/InpaintProcessor.swift",
    "Features/Inpainting/InpaintViewController.swift",
    "Features/Inpainting/SAMSegmentHelper.swift",
    "Features/Inpainting/SelectionOverlayView.swift",
    "Features/Mosaic/MosaicProcessor.swift",
    "Features/Mosaic/MosaicViewController.swift",
    "Features/Mosaic/FaceDetectionHelper.swift",
    "Features/DepthImage/DepthImageProcessor.swift",
    "Features/BackgroundRemoval/BackgroundMode.swift",
    "Features/BackgroundRemoval/BackgroundRemovalProcessor.swift",
    "Features/BackgroundRemoval/BackgroundRemovalViewController.swift",
    "Features/Enhancement/EnhancementMode.swift",
    "Features/Enhancement/EnhancementProcessor.swift",
    "Features/Enhancement/EnhancementViewController.swift",
    "Features/Enhancement/TileProcessor.swift",
    "Features/Enhancement/RealESRGANHelper.swift",
    "Features/Filters/FilterDefinition.swift",
    "Features/Filters/FilterProcessor.swift",
    "Features/Filters/FilterViewController.swift",
    "Features/TextRemoval/TextRemovalProcessor.swift",
    "Features/TextRemoval/TextRemovalViewController.swift",
    "Features/SmartCrop/SmartCropProcessor.swift",
    "Features/SmartCrop/SmartCropViewController.swift",
    "Features/SmartCrop/CropOverlayView.swift",
    "Features/Warmup/WarmupViewController.swift",
    "Features/Watermark/WatermarkConfig.swift",
    "Features/Watermark/WatermarkProcessor.swift",
    "Features/Watermark/WatermarkViewController.swift",
    "Features/History/HistoryCell.swift",
    "Features/History/HistoryViewController.swift",
]

# Groups to create: (group_path, group_name)
# Order matters - parent groups first
GROUPS = [
    ("Core", "Core"),
    ("Core/Protocols", "Protocols"),
    ("Core/Models", "Models"),
    ("Core/Services", "Services"),
    ("Core/Views", "Views"),
    ("Features", "Features"),
    ("Features/Home", "Home"),
    ("Features/Inpainting", "Inpainting"),
    ("Features/Mosaic", "Mosaic"),
    ("Features/DepthImage", "DepthImage"),
    ("Features/BackgroundRemoval", "BackgroundRemoval"),
    ("Features/Enhancement", "Enhancement"),
    ("Features/Filters", "Filters"),
    ("Features/TextRemoval", "TextRemoval"),
    ("Features/SmartCrop", "SmartCrop"),
    ("Features/Watermark", "Watermark"),
    ("Features/History", "History"),
    ("Features/Warmup", "Warmup"),
]

# Inpaint group UUID (from the pbxproj)
INPAINT_GROUP_UUID = "11CFF9F12B18D9FF008CFCA5"
# Inpaint target Sources build phase UUID
INPAINT_SOURCES_PHASE_UUID = "11CFF9EB2B18D9FF008CFCA5"


def make_uuid(seed: str, suffix: str = "") -> str:
    """Generate a deterministic 24-char hex UUID from a seed string."""
    h = hashlib.md5((seed + suffix).encode()).hexdigest().upper()
    return h[:24]


def main():
    with open(PBXPROJ_PATH, "r") as f:
        content = f.read()

    # Generate UUIDs for file references and build files
    file_ref_uuids = {}
    build_file_uuids = {}
    group_uuids = {}

    for filepath in NEW_FILES:
        filename = filepath.split("/")[-1]
        file_ref_uuids[filepath] = make_uuid(filepath, "_fileref")
        build_file_uuids[filepath] = make_uuid(filepath, "_buildfile")

    for group_path, group_name in GROUPS:
        group_uuids[group_path] = make_uuid(group_path, "_group")

    # 1. Add PBXBuildFile entries
    build_file_lines = []
    for filepath in NEW_FILES:
        filename = filepath.split("/")[-1]
        bf_uuid = build_file_uuids[filepath]
        fr_uuid = file_ref_uuids[filepath]
        line = f"\t\t{bf_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr_uuid} /* {filename} */; }};"
        build_file_lines.append(line)

    build_file_block = "\n".join(build_file_lines) + "\n"
    content = content.replace(
        "/* End PBXBuildFile section */",
        build_file_block + "/* End PBXBuildFile section */",
    )

    # 2. Add PBXFileReference entries
    file_ref_lines = []
    for filepath in NEW_FILES:
        filename = filepath.split("/")[-1]
        fr_uuid = file_ref_uuids[filepath]
        line = f"\t\t{fr_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};"
        file_ref_lines.append(line)

    file_ref_block = "\n".join(file_ref_lines) + "\n"
    content = content.replace(
        "/* End PBXFileReference section */",
        file_ref_block + "/* End PBXFileReference section */",
    )

    # 3. Add PBXGroup entries
    # Build mapping: group_path -> list of child file ref UUIDs
    group_children_files = {gp: [] for gp, _ in GROUPS}
    for filepath in NEW_FILES:
        parts = filepath.split("/")
        group_path = "/".join(parts[:-1])
        filename = parts[-1]
        fr_uuid = file_ref_uuids[filepath]
        group_children_files[group_path].append((fr_uuid, filename))

    # Build mapping: group_path -> list of child group UUIDs
    group_children_groups = {gp: [] for gp, _ in GROUPS}
    for group_path, group_name in GROUPS:
        parts = group_path.split("/")
        if len(parts) > 1:
            parent_path = "/".join(parts[:-1])
            if parent_path in group_children_groups:
                group_children_groups[parent_path].append(
                    (group_uuids[group_path], group_name)
                )

    # Generate group entries (add before /* End PBXGroup section */)
    group_lines = []
    for group_path, group_name in GROUPS:
        g_uuid = group_uuids[group_path]
        children = []
        # Add child groups first
        for child_uuid, child_name in group_children_groups[group_path]:
            children.append(f"\t\t\t\t{child_uuid} /* {child_name} */,")
        # Add child files
        for child_uuid, child_name in group_children_files[group_path]:
            children.append(f"\t\t\t\t{child_uuid} /* {child_name} */,")

        children_str = "\n".join(children)
        group_entry = (
            f"\t\t{g_uuid} /* {group_name} */ = {{\n"
            f"\t\t\tisa = PBXGroup;\n"
            f"\t\t\tchildren = (\n"
            f"{children_str}\n"
            f"\t\t\t);\n"
            f"\t\t\tpath = {group_name};\n"
            f"\t\t\tsourceTree = \"<group>\";\n"
            f"\t\t}};"
        )
        group_lines.append(group_entry)

    group_block = "\n".join(group_lines) + "\n"
    content = content.replace(
        "/* End PBXGroup section */",
        group_block + "/* End PBXGroup section */",
    )

    # 4. Add top-level groups (Core, Features) to the Inpaint group
    # Find the Inpaint group and add our new groups to its children
    core_uuid = group_uuids["Core"]
    features_uuid = group_uuids["Features"]

    # Insert the new group references into the Inpaint group's children list
    # We'll add them right after the opening of the children list
    inpaint_group_pattern = re.compile(
        r"(" + re.escape(INPAINT_GROUP_UUID) + r" /\* Inpaint \*/ = \{\s*"
        r"isa = PBXGroup;\s*"
        r"children = \(\s*)"
    )
    replacement = (
        r"\1"
        f"\t\t\t\t{core_uuid} /* Core */,\n"
        f"\t\t\t\t{features_uuid} /* Features */,\n"
    )
    content = inpaint_group_pattern.sub(replacement, content)

    # 5. Add build file references to the Inpaint target's Sources build phase
    # Find the Sources build phase for the Inpaint target
    sources_phase_pattern = re.compile(
        r"(" + re.escape(INPAINT_SOURCES_PHASE_UUID) + r" /\* Sources \*/ = \{\s*"
        r"isa = PBXSourcesBuildPhase;\s*"
        r"buildActionMask = 2147483647;\s*"
        r"files = \(\s*)"
    )

    new_build_refs = ""
    for filepath in NEW_FILES:
        filename = filepath.split("/")[-1]
        bf_uuid = build_file_uuids[filepath]
        new_build_refs += f"\t\t\t\t{bf_uuid} /* {filename} in Sources */,\n"

    content = sources_phase_pattern.sub(r"\1" + new_build_refs, content)

    # Write the modified file
    with open(PBXPROJ_PATH, "w") as f:
        f.write(content)

    print("Successfully added files to project.pbxproj")
    print(f"  - {len(NEW_FILES)} file references")
    print(f"  - {len(NEW_FILES)} build file entries")
    print(f"  - {len(GROUPS)} group entries")


if __name__ == "__main__":
    main()
