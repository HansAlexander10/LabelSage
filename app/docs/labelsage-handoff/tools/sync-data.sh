#!/bin/sh
# data/ is the source of truth. Copy it into the Swift package (app/shared/LabelSageCore), then run both engines.
set -e
cd "$(dirname "$0")/.."
PKG=../../shared/LabelSageCore
cp data/catalog.json $PKG/Sources/LabelSageCore/Resources/catalog.json
cp data/verdict-cases.json $PKG/Tests/LabelSageCoreTests/Resources/verdict-cases.json
python3 -I tools/reference_engine.py
if command -v swift >/dev/null 2>&1; then (cd $PKG && swift test); fi
