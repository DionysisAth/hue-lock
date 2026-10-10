#!/usr/bin/env bash
# Writes android/key.properties (+ the keystore) from the upload key secrets
# in the environment: KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS,
# KEY_PASSWORD. Prints "signed=true|false" for $GITHUB_OUTPUT.
#
# Without the secrets:
#   --throwaway  sign with a one-day key (proves signing works; not uploadable)
#   otherwise    write nothing: release builds fall back to the debug key
set -euo pipefail

if [ -z "${KEYSTORE_BASE64:-}" ]; then
  if [ "${1:-}" != "--throwaway" ]; then
    echo "signed=false"
    exit 0
  fi
  KEYSTORE_PASSWORD=throwaway-$RANDOM$RANDOM
  KEY_PASSWORD=$KEYSTORE_PASSWORD
  KEY_ALIAS=upload
  keytool -genkeypair -keystore android/app/upload-keystore.jks \
    -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 1 \
    -alias upload -dname "CN=CI" \
    -storepass "$KEYSTORE_PASSWORD" -keypass "$KEY_PASSWORD" >&2
  echo "signed=false"
else
  echo "$KEYSTORE_BASE64" | base64 --decode > android/app/upload-keystore.jks
  echo "signed=true"
fi
{
  echo "storeFile=upload-keystore.jks"
  echo "storePassword=$KEYSTORE_PASSWORD"
  echo "keyAlias=$KEY_ALIAS"
  echo "keyPassword=$KEY_PASSWORD"
} > android/key.properties
