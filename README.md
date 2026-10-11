# Switcher

Переключалка раскладки для macOS: короткое нажатие Option меняет раскладку последнего набранного слова или выделенного текста.

## Готовая сборка

Скачайте `Switcher.zip` со страницы [Releases](https://github.com/ganiushin/switcher/releases/latest) (Apple Silicon, macOS 13+). Приложение не нотаризовано, поэтому после распаковки снимите карантин:

```sh
xattr -dr com.apple.quarantine Switcher.app
```

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
