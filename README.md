# Switcher

Переключалка раскладки для macOS: короткое нажатие Option меняет раскладку последнего набранного слова или выделенного текста.

## Сборка

Нужны Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh
```

## Запуск

```sh
cp -R build/Switcher.app /Applications/
open /Applications/Switcher.app
```

При первом запуске выдайте доступ: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → Switcher. После пересборки доступ нужно выдать заново.
