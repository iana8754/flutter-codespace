from pathlib import Path

p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()

if 'android.permission.INTERNET' not in s:
    s = s.replace(
        '<application',
        '<uses-permission android:name="android.permission.INTERNET"/>\n'
        '    <uses-permission android:name="android.permission.CAMERA"/>\n'
        '    <application',
        1,
    )

s = s.replace('android:label="my_cloud"', 'android:label="Моё облако"')
p.write_text(s)
print('AndroidManifest.xml patched successfully')
