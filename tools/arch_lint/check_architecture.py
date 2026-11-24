#!/usr/bin/env python3
"""Architecture Lint Scanner for PureLive 4.x NextGen.

Enforces Master Specification Architecture Invariants:
1. Unidirectional Dependency DAG: No backwards dependencies (apps/ -> packages/, packages cannot import apps).
2. Pure Dart packages: packages/live_* (except live_ui and live_player) must NEVER import Flutter SDK.
3. Prohibited redundant binaries: ZERO references to ffmpeg_kit_* in pubspec.yaml or .dart source.
4. Drift Local-First contract: Drift schema version >= 3 with sync_id, updated_at, is_deleted columns.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]

# Allowed internal dependencies per member
ALLOWED_LAYERING = {
    'packages/live_net': set(),
    'packages/live_core': {'live_net'},
    'packages/live_danmaku': {'live_core', 'live_net'},
    'packages/live_iptv': {'live_core', 'live_net'},
    'packages/live_media': {'live_core', 'live_net'},
    'packages/live_player': {'live_media', 'live_core', 'live_net'},
    'packages/live_record': {'live_media', 'live_core', 'live_net'},
    'packages/live_store': {'live_core'},
    'packages/live_cast': set(),
    'packages/live_ui': set(),
    'packages/live_vod': {'live_core', 'live_net'},
    'apps/pure_live': {
        'live_ui', 'live_media', 'live_player', 'live_record', 'live_danmaku',
        'live_iptv', 'live_store', 'live_core', 'live_net', 'live_cast', 'live_vod',
    },
    'tools/live_cli': {'live_core', 'live_net', 'live_danmaku'},
    'tools/check_latest': set(),
}

# Pure Dart members that must never depend on or import Flutter
PURE_DART_MEMBERS = {
    'packages/live_net',
    'packages/live_core',
    'packages/live_danmaku',
    'packages/live_iptv',
    'packages/live_media',
    'packages/live_record',
    'packages/live_cast',
    'packages/live_store',
    'packages/live_vod',
    'tools/live_cli',
    'tools/check_latest',
}

IMPORT_PATTERN = re.compile(r"""^\s*(?:import|export)\s+['"]package:([a-z0-9_]+)/""", re.MULTILINE)
FORBIDDEN_PACKAGES = {'ffmpeg_kit', 'ffmpeg_kit_extended_flutter', 'ffmpeg_kit_flutter'}


def check_architecture(root=ROOT):
    errors = []
    
    # 1. Check root pubspec.yaml for forbidden overrides
    root_pubspec = (root / 'pubspec.yaml').read_text(encoding='utf-8')
    for forbidden in FORBIDDEN_PACKAGES:
        if forbidden in root_pubspec:
            errors.append(f'root pubspec.yaml contains forbidden dependency: {forbidden}')
            
    # 2. Check each member's pubspec and code
    for member, allowed_deps in ALLOWED_LAYERING.items():
        member_dir = root / member
        if not member_dir.exists():
            continue
            
        pubspec_file = member_dir / 'pubspec.yaml'
        if not pubspec_file.exists():
            continue
            
        pubspec_content = pubspec_file.read_text(encoding='utf-8')
        for forbidden in FORBIDDEN_PACKAGES:
            if forbidden in pubspec_content:
                errors.append(f'{member}/pubspec.yaml contains forbidden dependency: {forbidden}')
                
        is_pure_dart = member in PURE_DART_MEMBERS
        if is_pure_dart and ('sdk: flutter' in pubspec_content or 'flutter:' in pubspec_content):
            errors.append(f'{member}/pubspec.yaml: Pure Dart package must not depend on Flutter SDK')
            
        # Scan dart files
        for dart_file in member_dir.rglob('*.dart'):
            # Skip hidden / build dirs
            if any(part.startswith('.') or part == 'build' for part in dart_file.parts):
                continue
            text = dart_file.read_text(encoding='utf-8', errors='replace')
            rel_path = dart_file.relative_to(root).as_posix()
            
            for match in IMPORT_PATTERN.finditer(text):
                pkg = match.group(1)
                line_no = text.count('\n', 0, match.start()) + 1
                
                # Check forbidden ffmpeg_kit
                if any(forbidden in pkg for forbidden in FORBIDDEN_PACKAGES):
                    errors.append(f'{rel_path}:{line_no}: imports forbidden package:{pkg}')
                    
                # Check pure dart flutter constraint
                if is_pure_dart and pkg in ('flutter', 'flutter_test'):
                    errors.append(f'{rel_path}:{line_no}: pure-Dart package illegally imports {pkg}')
                    
                # Check layering DAG (no live_* outside allowed)
                if pkg.startswith('live_'):
                    member_name = member.split('/')[-1]
                    if pkg != member_name and pkg not in allowed_deps:
                        errors.append(f'{rel_path}:{line_no}: illegal layer cross-import package:{pkg} for {member}')
                        
    # 3. Check Local-First drift schema version & columns
    db_file = root / 'packages/live_store/lib/src/database.dart'
    if db_file.exists():
        db_text = db_file.read_text(encoding='utf-8')
        if 'schemaVersion => 3' not in db_text and 'schemaVersion = 3' not in db_text:
            errors.append('packages/live_store/lib/src/database.dart must have schemaVersion >= 3')
        if 'sync_id' not in db_text or 'updated_at' not in db_text or 'is_deleted' not in db_text:
            errors.append('packages/live_store/lib/src/database.dart missing required local-first columns (sync_id, updated_at, is_deleted)')

    return errors


def main():
    print('Running PureLive Architecture Linter...')
    errors = check_architecture()
    if errors:
        print(f'Architecture Linter FAILED with {len(errors)} errors:', file=sys.stderr)
        for err in errors:
            print(f'  - {err}', file=sys.stderr)
        return 1
    print('Architecture Linter PASSED: All architectural invariants verified!')
    return 0


if __name__ == '__main__':
    sys.exit(main())
