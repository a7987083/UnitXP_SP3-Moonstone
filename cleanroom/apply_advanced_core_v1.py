#!/usr/bin/env python3
"""Install MoonMarker advanced marker state schema and security guard layer."""

from __future__ import annotations

import argparse
import base64
import hashlib
import shutil
import zlib
from pathlib import Path


PAYLOAD_SHA256 = {
    "MoonMarkerAdvancedState.cpp": "6df374c49cadd64424aa6eb590dd05d361317572e0758f17f9067c069cbfe543",
    "AdvancedCoreDiagnostics.lua": "9d874763205ffc585d2bee330475cedd43b85d35ecd6fb5956c43667ac037dbc",
}


def decode_payload(source_dir: Path, name: str) -> bytes:
    payload = source_dir / f"{name}.zlib.b64"
    if not payload.is_file():
        raise RuntimeError(f"missing advanced core payload: {payload}")
    encoded = "".join(payload.read_text(encoding="ascii").split())
    raw = zlib.decompress(base64.b64decode(encoded))
    actual = hashlib.sha256(raw).hexdigest()
    if actual != PAYLOAD_SHA256[name]:
        raise RuntimeError(f"{name} checksum mismatch: {actual}")
    return raw


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--addon", required=True)
    parser.add_argument("--source-dir", required=True)
    args = parser.parse_args()

    upstream = Path(args.upstream)
    addon_root = Path(args.addon) / "MoonMarker"
    source_dir = Path(args.source_dir)

    header_source = source_dir / "MoonMarkerAdvancedState.h"
    if not header_source.is_file():
        raise RuntimeError(f"missing advanced core source: {header_source}")
    shutil.copyfile(header_source, upstream / "MoonMarkerAdvancedState.h")
    (upstream / "MoonMarkerAdvancedState.cpp").write_bytes(
        decode_payload(source_dir, "MoonMarkerAdvancedState.cpp"))
    (addon_root / "AdvancedCoreDiagnostics.lua").write_bytes(
        decode_payload(source_dir, "AdvancedCoreDiagnostics.lua"))

    toc_path = addon_root / "MoonMarker.toc"
    toc = toc_path.read_text(encoding="utf-8-sig")
    if "AdvancedCoreDiagnostics.lua" not in toc:
        anchor = "GuildAdvanced.lua\n"
        if anchor not in toc:
            raise RuntimeError("MoonMarker.toc missing GuildAdvanced.lua anchor")
        toc = toc.replace(anchor, anchor + "AdvancedCoreDiagnostics.lua\n", 1)
    toc_path.write_text(toc, encoding="utf-8", newline="\n")

    make_path = upstream / "Makefile"
    makefile = make_path.read_text(encoding="utf-8-sig")
    makefile = replace_once(
        makefile,
        "            MoonMarkerM2Scanner.cpp \\\n",
        "            MoonMarkerM2Scanner.cpp \\\n            MoonMarkerAdvancedState.cpp \\\n",
        "advanced state Makefile source",
    )
    make_path.write_text(makefile, encoding="utf-8", newline="\n")

    auth_path = upstream / "MoonMarkerGuildAuth.cpp"
    auth = auth_path.read_text(encoding="utf-8")
    auth = replace_once(
        auth,
        '#include "MoonMarkerM2Scanner.h"\n',
        '#include "MoonMarkerAdvancedState.h"\n#include "MoonMarkerM2Scanner.h"\n',
        "advanced state auth include",
    )
    auth = replace_once(
        auth,
        'const char* kTargetCommit = "MoonMarker.Targeting.Commit";\n',
        'const char* kTargetCommit = "MoonMarker.Targeting.Commit";\n'
        'const char* kAdvancedCoreStatus = "MoonMarker.Advanced.Core.Status";\n'
        'const char* kAdvancedCorePolicy = "MoonMarker.Advanced.Core.Policy";\n'
        'const char* kAdvancedCoreSelfTest = "MoonMarker.Advanced.Core.SelfTest";\n',
        "advanced core command constants",
    )

    old_create = '''int createAdvancedAt(void* luaState, const std::string& path,
                     C3Vector position, float scale, float yaw) {
    position.z += 0.05f;
    std::string normalizedPath;
    if (!nativeM2Test::createAdvancedPreview(path, position, scale, yaw, normalizedPath)) {
        const auto status = nativeM2Test::advancedPreviewStatus();
        return pushFailure(luaState, status.lastErrorStage);
    }
    lua_pushboolean(luaState, 1);
    lua_pushnumber(luaState, position.x);
    lua_pushnumber(luaState, position.y);
    lua_pushnumber(luaState, position.z);
    lua_pushstring(luaState, normalizedPath);
    return 5;
}
'''
    new_create = '''int createAdvancedAt(void* luaState, const std::string& path,
                     C3Vector position, float scale, float yaw) {
    C3Vector actorPosition = {};
    if (!nativeM2Test::playerFeetPosition(actorPosition)) {
        return pushFailure(luaState, "PLAYER_POSITION_UNAVAILABLE");
    }

    moonMarkerAdvancedState::MarkerDefinition marker;
    marker.primaryPath = path;
    marker.primary.position = position;
    marker.primary.scale = scale;
    marker.primary.yawDegrees = yaw;
    marker.localOnly = true;

    const auto validated = moonMarkerAdvancedState::normalizeAndValidate(
        marker, false, &actorPosition,
        moonMarkerAdvancedState::kAbsoluteMaxDistance);
    if (!validated) return pushFailure(luaState, validated.name);

    C3Vector renderPosition = marker.primary.position;
    renderPosition.z += 0.05f;
    std::string rendererPath;
    if (!nativeM2Test::createAdvancedPreview(marker.primaryPath, renderPosition,
            marker.primary.scale, marker.primary.yawDegrees, rendererPath)) {
        const auto status = nativeM2Test::advancedPreviewStatus();
        return pushFailure(luaState, status.lastErrorStage);
    }

    const auto committed = moonMarkerAdvancedState::commitLocalDraft(
        marker, isAuthorized(luaState), &actorPosition,
        moonMarkerAdvancedState::kAbsoluteMaxDistance);
    if (!committed) {
        nativeM2Test::clearAdvancedPreview();
        return pushFailure(luaState, committed.name);
    }

    lua_pushboolean(luaState, 1);
    lua_pushnumber(luaState, renderPosition.x);
    lua_pushnumber(luaState, renderPosition.y);
    lua_pushnumber(luaState, renderPosition.z);
    lua_pushstring(luaState, rendererPath);
    return 5;
}
'''
    auth = replace_once(auth, old_create, new_create, "advanced create core validation")

    old_clear = '''    if (command == cmd_MoonMarker_Advanced_ClearPreview()) {
        nativeM2Test::clearAdvancedPreview();
        lua_pushboolean(luaState, 1);
        lua_pushstring(luaState, "CLEARED");
        return 2;
    }
'''
    new_clear = '''    if (command == cmd_MoonMarker_Advanced_ClearPreview()) {
        nativeM2Test::clearAdvancedPreview();
        moonMarkerAdvancedState::clearLocalDraft("LOCAL_PREVIEW_CLEARED");
        lua_pushboolean(luaState, 1);
        lua_pushstring(luaState, "CLEARED");
        return 2;
    }
'''
    auth = replace_once(auth, old_clear, new_clear, "clear local draft")

    old_transform = '''    if (command == cmd_MoonMarker_Advanced_SetPreviewTransform()) {
        if (lua_gettop(luaState) < 3 || !lua_isnumber(luaState, 2) || !lua_isnumber(luaState, 3))
            return pushFailure(luaState, "TRANSFORM_REQUIRED");
        const float scale = static_cast<float>(lua_tonumber(luaState, 2));
        const float yaw = static_cast<float>(lua_tonumber(luaState, 3));
        if (!nativeM2Test::setAdvancedPreviewTransform(scale, yaw))
            return pushFailure(luaState, "TRANSFORM_REJECTED");
        lua_pushboolean(luaState, 1);
        lua_pushnumber(luaState, scale);
        lua_pushnumber(luaState, yaw);
        return 3;
    }
'''
    new_transform = '''    if (command == cmd_MoonMarker_Advanced_SetPreviewTransform()) {
        if (lua_gettop(luaState) < 3 || !lua_isnumber(luaState, 2) || !lua_isnumber(luaState, 3))
            return pushFailure(luaState, "TRANSFORM_REQUIRED");

        moonMarkerAdvancedState::MarkerDefinition marker;
        if (!moonMarkerAdvancedState::getLocalDraft(marker))
            return pushFailure(luaState, "LOCAL_DRAFT_NOT_FOUND");
        marker.primary.scale = static_cast<float>(lua_tonumber(luaState, 2));
        marker.primary.yawDegrees = static_cast<float>(lua_tonumber(luaState, 3));

        C3Vector actorPosition = {};
        if (!nativeM2Test::playerFeetPosition(actorPosition))
            return pushFailure(luaState, "PLAYER_POSITION_UNAVAILABLE");
        const auto validated = moonMarkerAdvancedState::normalizeAndValidate(
            marker, false, &actorPosition,
            moonMarkerAdvancedState::kAbsoluteMaxDistance);
        if (!validated) return pushFailure(luaState, validated.name);

        if (!nativeM2Test::setAdvancedPreviewTransform(
                marker.primary.scale, marker.primary.yawDegrees))
            return pushFailure(luaState, "TRANSFORM_REJECTED");
        const auto committed = moonMarkerAdvancedState::commitLocalDraft(
            marker, isAuthorized(luaState), &actorPosition,
            moonMarkerAdvancedState::kAbsoluteMaxDistance);
        if (!committed) return pushFailure(luaState, committed.name);

        lua_pushboolean(luaState, 1);
        lua_pushnumber(luaState, marker.primary.scale);
        lua_pushnumber(luaState, marker.primary.yawDegrees);
        return 3;
    }
'''
    auth = replace_once(auth, old_transform, new_transform, "transform core validation")

    insert_before = '''    if (command == cmd_MoonMarker_Advanced_ScanM2_Start()) {
'''
    core_handlers = '''    if (command == kAdvancedCoreStatus) {
        const auto core = moonMarkerAdvancedState::status();
        lua_pushboolean(luaState, 1);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kSchemaVersion);
        lua_pushboolean(luaState, core.localDraftActive ? 1 : 0);
        lua_pushnumber(luaState, static_cast<double>(core.teamMarkerCount));
        lua_pushnumber(luaState, static_cast<double>(core.maxTeamMarkers));
        lua_pushnumber(luaState, static_cast<double>(core.acceptedMutations));
        lua_pushnumber(luaState, static_cast<double>(core.rejectedValidation));
        lua_pushnumber(luaState, static_cast<double>(core.rejectedAccess));
        lua_pushnumber(luaState, static_cast<double>(core.rejectedRate));
        lua_pushnumber(luaState, static_cast<double>(core.rejectedSequence));
        lua_pushnumber(luaState, static_cast<double>(core.worldContextResets));
        lua_pushstring(luaState, core.lastError);
        return 12;
    }

    if (command == kAdvancedCorePolicy) {
        lua_pushboolean(luaState, 1);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kSchemaVersion);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kMaxTeamMarkers);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kMaxModelPathLength);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kMinScale);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kMaxScale);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kMinTopHeight);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kMaxTopHeight);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kDefaultMaxDistance);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kAbsoluteMaxDistance);
        lua_pushnumber(luaState, moonMarkerAdvancedState::kRateLimitPerSecond);
        return 11;
    }

    if (command == kAdvancedCoreSelfTest) {
        std::size_t passed = 0;
        std::size_t total = 0;
        std::string firstFailure;
        const bool ok = moonMarkerAdvancedState::runSelfTest(
            passed, total, firstFailure);
        lua_pushboolean(luaState, ok ? 1 : 0);
        lua_pushnumber(luaState, static_cast<double>(passed));
        lua_pushnumber(luaState, static_cast<double>(total));
        if (firstFailure.empty()) lua_pushnil(luaState);
        else lua_pushstring(luaState, firstFailure);
        return 4;
    }

'''
    auth = replace_once(auth, insert_before, core_handlers + insert_before,
                        "advanced core handlers")
    auth_path.write_text(auth, encoding="utf-8", newline="\n")

    native_path = upstream / "nativeM2Test.cpp"
    native = native_path.read_text(encoding="utf-8")
    native = replace_once(
        native,
        '#include <Windows.h>\n\nnamespace nativeM2Test {',
        '#include <Windows.h>\n\n#include "MoonMarkerAdvancedState.h"\n\nnamespace nativeM2Test {',
        "advanced state native include",
    )
    native = replace_once(
        native,
        '''void update() {
    resetProjected();
    void* liveContext = currentContext();
''',
        '''void update() {
    resetProjected();
    void* liveContext = currentContext();
    moonMarkerAdvancedState::observeWorldContext(
        reinterpret_cast<std::uintptr_t>(liveContext));
''',
        "world context lifecycle hook",
    )
    native = replace_once(
        native,
        '''void clear() {
    for (Slot& slot : gSlots) releaseSlot(slot, false);
''',
        '''void clear() {
    moonMarkerAdvancedState::clearAll("NATIVE_CLEAR_ALL");
    for (Slot& slot : gSlots) releaseSlot(slot, false);
''',
        "native clear lifecycle hook",
    )
    native_path.write_text(native, encoding="utf-8", newline="\n")

    checks = {
        upstream / "MoonMarkerAdvancedState.h": (
            "struct MarkerDefinition",
            "kMaxTeamMarkers = 16",
            "kAbsoluteMaxDistance = 120.0f",
            "acceptTeamMutation",
            "observeWorldContext",
        ),
        upstream / "MoonMarkerAdvancedState.cpp": (
            "PARENT_PATH_TRAVERSAL",
            "SCALE_OUT_OF_RANGE",
            "DISTANCE_EXCEEDED",
            "RATE_LIMITED",
            "SEQUENCE_STALE",
            "runSelfTest",
        ),
        auth_path: (
            "MoonMarker.Advanced.Core.Status",
            "MoonMarker.Advanced.Core.Policy",
            "MoonMarker.Advanced.Core.SelfTest",
            "commitLocalDraft",
        ),
        native_path: (
            "observeWorldContext",
            "NATIVE_CLEAR_ALL",
        ),
        addon_root / "AdvancedCoreDiagnostics.lua": (
            'SLASH_MOONMARKERCORE1 = "/mmcore"',
            'SLASH_MOONMARKERCOREPOLICY1 = "/mmcorepolicy"',
            'SLASH_MOONMARKERCORETEST1 = "/mmcoretest"',
        ),
    }
    for path, tokens in checks.items():
        text = path.read_text(encoding="utf-8")
        for token in tokens:
            if token not in text:
                raise RuntimeError(f"{path.name} missing token: {token}")


if __name__ == "__main__":
    main()
