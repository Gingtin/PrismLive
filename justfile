# PureLive 4.x NextGen justfile
# Unified DX tasks across developer machines and CI pipelines

default:
    @just --list

# 1. Environment setup: apply Flutter SDK patch and resolve workspace dependencies
setup:
    python tools/flutter_sdk/prepare.py --apply
    flutter pub get

# 2. Workspace verification: architecture lint & full-workspace package tests
test:
    python tools/arch_lint/check_architecture.py
    dart test packages/live_iptv
    dart test packages/live_store
    flutter test packages/live_ui
    flutter test apps/pure_live/test/features/privacy/nsfw_privacy_test.dart
    flutter test packages/live_player/test/decoder_budget_manager_test.dart

# 3. Android build with specified target ABI (default: arm64-v8a)
build-android abi="arm64-v8a":
    cd apps/pure_live && flutter build apk --target-platform android-{{abi}}

# 4. Stream probe: inspect live stream media parameters as JSON
probe url:
    ffprobe -v quiet -print_format json -show_format -show_streams "{{url}}"

# 5. Full quality gate: architecture rules, dependency direction, fixtures, UI structure
gate:
    python tools/arch_lint/check_architecture.py
    python tools/gate/check_deps.py
    python tools/gate/check_fixtures.py
    python tools/gate/check_ui_structure.py
