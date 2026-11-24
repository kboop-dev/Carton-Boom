#!/usr/bin/env bash
set -e
BUILD=$(date +%s)
flutter pub get
flutter build web --release --pwa-strategy=none --build-number=$BUILD
firebase deploy --only hosting,firestore:rules
echo "Publicado. Versión $BUILD"