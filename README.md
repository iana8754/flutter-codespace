# Моё облако (Flutter + Supabase)

1. supabase.com -> New project (бесплатно, без карты).
2. SQL Editor -> вставить supabase_setup.sql -> Run.
3. Authentication -> Providers -> Email -> выключить "Confirm email" (чтобы вход работал сразу).
4. Settings -> API: скопировать Project URL и anon public key в lib/main.dart.
5. Залить проект в GitHub-репозиторий (в Codespaces: git add . && git commit -m init && git push).
6. GitHub -> вкладка Actions -> Build APK -> когда завершится, внизу Artifacts -> my-cloud-apk (скачать).
