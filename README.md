# MTProxy Private Deploy

`install-mtproxy.sh` — это installer и operator entrypoint для приватного MTProto proxy на Ubuntu 24.04.

Поддерживаются два режима:
- `ENGINE=official` — официальный `TelegramMessenger/MTProxy`
- `ENGINE=stealth` — `telemt` с профилями `ee`, `dd`, `classic`

## Что это

Проект поднимает приватный proxy на одном VPS и управляет им через один скрипт.

Ключевые свойства:
- домен обязателен при первой установке;
- сервис публикуется на одном публичном порту, по умолчанию `443/tcp`;
- создается bundle из нескольких ссылок, а не одна ссылка;
- секреты и `tg://` ссылки не печатаются в обычном выводе;
- есть команды для статуса, health-check, ротации ссылок, ручного refresh и удаления.

## Как это работает

После `install` скрипт:
- собирает и устанавливает выбранный runtime;
- сохраняет deployment manifest и runtime artifacts в `/etc/mtproxy`;
- создает systemd unit'ы и запускает сервис;
- генерирует managed bundle ссылок;
- для `ENGINE=official` включает daily refresh Telegram config через systemd timer.

По умолчанию после установки выводится только безопасная сводка. Чтобы получить реальные клиентские ссылки, нужно вызвать `share-links`.

## Требования

- Ubuntu 24.04
- root-доступ
- домен, который уже указывает на VPS
- открытый TCP-порт `443` или другой `PUBLIC_PORT`

Для `ENGINE=stealth`:
- `DECOY_MODE=upstream-forward` требует рабочий HTTPS upstream;
- `DECOY_MODE=local-https` может использовать готовый сертификат или сгенерировать self-signed сертификат.

## Установка и запуск

### Быстрый старт: official

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh install
```

### Быстрый старт: stealth

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh
sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash ./install-mtproxy.sh install
```

### После установки

Сервис запускается автоматически.

Проверить состояние:

```bash
sudo bash ./install-mtproxy.sh status
sudo bash ./install-mtproxy.sh health
```

Получить клиентские ссылки:

```bash
sudo bash ./install-mtproxy.sh share-links
```

Посмотреть только redacted metadata:

```bash
sudo bash ./install-mtproxy.sh list-links
```

## Основные команды

```bash
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh install
sudo bash ./install-mtproxy.sh status
sudo bash ./install-mtproxy.sh health
sudo bash ./install-mtproxy.sh share-links
sudo bash ./install-mtproxy.sh list-links
sudo bash ./install-mtproxy.sh rotate-link <name>
sudo bash ./install-mtproxy.sh rotate-all-links
sudo bash ./install-mtproxy.sh refresh-telegram-config
sudo bash ./install-mtproxy.sh restart
sudo bash ./install-mtproxy.sh check-domain
sudo bash ./install-mtproxy.sh test-decoy
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh migrate-install
sudo bash ./install-mtproxy.sh uninstall
```

Коротко по назначению:
- `install` — установка или повторная реконсиляция конфигурации;
- `status` — состояние сервиса, redacted links и последние логи;
- `health` — диагностика сервиса и конфигурации;
- `share-links` — намеренно показать реальные клиентские ссылки;
- `list-links` — показать bundle без раскрытия секретов;
- `rotate-link <name>` — перевыпустить одну ссылку;
- `rotate-all-links` — перевыпустить все ссылки;
- `refresh-telegram-config` — вручную обновить Telegram config;
- `restart` — перезапустить managed runtime;
- `check-domain` — проверить DNS домена;
- `test-decoy` — проверить decoy contour;
- `migrate-install` — миграция со старой раскладки;
- `uninstall` — удалить сервис и managed artifacts.

## Как обновить

Обновление выполняется той же командой `install`.

### Обновить current install

```bash
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh install
```

### Обновить и переключиться на stealth

```bash
sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash ./install-mtproxy.sh install
```

### Обновить только Telegram config вручную

```bash
sudo bash ./install-mtproxy.sh refresh-telegram-config
```

## Как удалить

```bash
sudo bash ./install-mtproxy.sh uninstall
```

Команда останавливает и удаляет managed systemd units, бинарники, helper scripts, конфиги и state каталоги.

## Лицензия

Проект распространяется под лицензией [MIT](LICENSE).
