#!/usr/bin/env bash
# Запускать после `flutter create --platforms=android .`
set -e
KTS=android/app/build.gradle.kts
if [ ! -f "$KTS" ]; then
  echo "Не найден $KTS. Сначала выполните: flutter create --platforms=android ."
  exit 1
fi
# Яндекс MapKit требует Android 8.0+ (API 26)
sed -i -E 's/minSdk = (flutter\.minSdkVersion|[0-9]+)/minSdk = 26/' "$KTS"
# Зависимость, которую просит документация MapKit
if ! grep -q play-services-location "$KTS"; then
  cat >> "$KTS" <<'X'

dependencies {
    implementation("com.google.android.gms:play-services-location:21.1.0")
}
X
fi
echo "Android настроен."
