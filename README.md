# 🦺 MTProxy Private Deploy (Ubuntu 24.04)

Скрипт для установки и управления **private MTProto proxy** на Ubuntu 24.04.

Текущая реализация поддерживает два runtime path:

- `ENGINE=official` — официальный `TelegramMessenger/MTProxy`;
- `ENGINE=stealth` — `telemt` с поддержкой `ee`, `dd`, `classic` и engine-aware bundle.

Скрипт переводит установку на доменно-обязательный контракт и quiet-by-default модель:

- `PUBLIC_DOMAIN` обязателен при первой установке;
- ссылки и secret не печатаются по умолчанию;
- создается managed bundle из нескольких ссылок;
- есть persisted manifest, link slots, ротация ссылок и health/status;
- для official engine работает daily refresh Telegram config;
- для stealth engine есть реальный runtime adapter, `TLS_DOMAIN`, upstream decoy forwarding и local loopback HTTPS decoy.

---

## Возможности

- установка зависимостей и сборка выбранного engine из исходников;
- обязательный домен для публичного подключения;
- persisted deployment manifest;
- protected artifact layout:
  - `/etc/mtproxy/config/`
  - `/etc/mtproxy/secrets/`
  - `/etc/mtproxy/links/`
  - `/etc/mtproxy/runtime/`
- bundle из нескольких ссылок;
- `LINK_STRATEGY=per-device` с именованными device links и shared fallback;
- quiet-by-default install/status;
- ротация одной ссылки или всех ссылок;
- engine-aware secret storage и link rendering;
- автоматический daily refresh `proxy-multi.conf` через systemd timer для `ENGINE=official`;
- stealth runtime через `telemt` для `ENGINE=stealth`;
- `DECOY_MODE=local-https` с отдельным local-only HTTPS decoy service на loopback;
- `check-domain`, `test-decoy` и явный `migrate-install` для финального operator workflow.

---

## Требования

- Ubuntu 24.04
- Root-доступ
- Домен, указывающий на VPS
- Открытый TCP-порт (по умолчанию `443`)

Для `ENGINE=stealth`:

- если используется `DECOY_MODE=upstream-forward`, нужен реальный upstream HTTPS target;
- если используется `DECOY_MODE=local-https`, поднимается отдельный local-only HTTPS decoy service на `127.0.0.1`;
- для `local-https` можно либо передать `DECOY_CERT_PATH` + `DECOY_KEY_PATH`, либо позволить скрипту сгенерировать self-signed certificate для `DECOY_DOMAIN`.

---

## Установка

### Official engine

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh install
```

### Stealth engine

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh
sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash ./install-mtproxy.sh install
```

### Stealth engine + per-device links

```bash
sudo \
  PUBLIC_DOMAIN=proxy.example.com \
  ENGINE=stealth \
  LINK_STRATEGY=per-device \
  DEVICE_NAMES=phone,desktop,tablet \
  bash ./install-mtproxy.sh install
```

### Stealth engine + upstream decoy

```bash
sudo \
  PUBLIC_DOMAIN=proxy.example.com \
  ENGINE=stealth \
  TLS_DOMAIN=proxy.example.com \
  DECOY_MODE=upstream-forward \
  DECOY_TARGET_HOST=site.example.com \
  DECOY_TARGET_PORT=443 \
  bash ./install-mtproxy.sh install
```

### Stealth engine + local HTTPS decoy

С самоподписанным сертификатом, который скрипт сгенерирует сам:

```bash
sudo \
  PUBLIC_DOMAIN=proxy.example.com \
  ENGINE=stealth \
  TLS_DOMAIN=proxy.example.com \
  DECOY_MODE=local-https \
  DECOY_DOMAIN=www.example.com \
  bash ./install-mtproxy.sh install
```

С уже подготовленным сертификатом:

```bash
sudo \
  PUBLIC_DOMAIN=proxy.example.com \
  ENGINE=stealth \
  TLS_DOMAIN=proxy.example.com \
  DECOY_MODE=local-https \
  DECOY_DOMAIN=www.example.com \
  DECOY_CERT_PATH=/root/certs/www.example.com.crt \
  DECOY_KEY_PATH=/root/certs/www.example.com.key \
  bash ./install-mtproxy.sh install
```

---

## Поведение после установки

После установки скрипт выводит только безопасную сводку:

- домен;
- порт;
- engine;
- TLS domain;
- decoy mode;
- decoy target/domain, если выбран decoy;
- количество сгенерированных links.

Сами `secret` и `tg://` ссылки не печатаются.

Чтобы намеренно открыть bundle:

```bash
sudo bash ./install-mtproxy.sh share-links
```

Чтобы увидеть только redacted metadata:

```bash
sudo bash ./install-mtproxy.sh list-links
```

---

## Bundle по умолчанию

### `ENGINE=official`

- при `PRIMARY_PROFILE=dd`:
  - `primary-dd`
  - `reserve-dd`
  - `fallback-classic`
- при `PRIMARY_PROFILE=classic`:
  - `primary-classic`
  - `reserve-classic`
  - `fallback-dd`

### `ENGINE=stealth`

- при `PRIMARY_PROFILE=ee`:
  - `primary-ee`
  - `reserve-ee`
  - `fallback-dd`
- при `PRIMARY_PROFILE=dd`:
  - `primary-dd`
  - `reserve-dd`
  - `fallback-classic`
- при `PRIMARY_PROFILE=classic`:
  - `primary-classic`
  - `reserve-classic`
  - `fallback-dd`

### `LINK_STRATEGY=per-device`

Пример для `DEVICE_NAMES=phone,desktop,tablet` и `ENGINE=stealth PRIMARY_PROFILE=ee`:

- `phone-ee`
- `desktop-ee`
- `tablet-ee`
- `shared-fallback-dd`

---

## Команды

### Установка / обновление структуры

```bash
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh install
sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash ./install-mtproxy.sh install
```

### Статус

```bash
sudo bash ./install-mtproxy.sh status
```

### Health checks

```bash
sudo bash ./install-mtproxy.sh health
```

### Проверить DNS домена до или после установки

```bash
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh check-domain
```

Если установка уже выполнена, можно запустить без переменных окружения — команда возьмет домен из manifest.

### Проверить decoy contour

```bash
sudo bash ./install-mtproxy.sh test-decoy
```

Для `DECOY_MODE=upstream-forward` команда проверяет TCP/TLS доступность upstream target.
Для `DECOY_MODE=local-https` команда проверяет local service, loopback HTTPS probe и SAN сертификата.

### Показать ссылки намеренно

```bash
sudo bash ./install-mtproxy.sh share-links
```

### Показать список ссылок без раскрытия secret

```bash
sudo bash ./install-mtproxy.sh list-links
```

### Ротация одной ссылки

```bash
sudo bash ./install-mtproxy.sh rotate-link primary-ee
sudo bash ./install-mtproxy.sh rotate-link primary-dd
```

### Ротация всех ссылок

```bash
sudo bash ./install-mtproxy.sh rotate-all-links
```

### Обновление Telegram config вручную

```bash
sudo bash ./install-mtproxy.sh refresh-telegram-config
```

Для `ENGINE=stealth` эта команда не требуется и завершится без обновления upstream artifacts.

Совместимый alias:

```bash
sudo bash ./install-mtproxy.sh update-config
```

### Миграция со старой single-secret установки

```bash
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh migrate-install
```

Что делает команда:

- подхватывает legacy secret и upstream Telegram artifacts, если они уже существуют;
- пытается извлечь `PUBLIC_PORT`, `INTERNAL_PORT` и `WORKERS` из legacy `mtproxy.service`, если manifest еще не создан;
- переносит установку в managed artifact model без ручной правки файлов.

### Перезапуск

```bash
sudo bash ./install-mtproxy.sh restart
```

### Удаление

```bash
sudo bash ./install-mtproxy.sh uninstall
```

---

## Переменные окружения

| Переменная | По умолчанию | Описание |
|---|---:|---|
| `PUBLIC_DOMAIN` | — | Обязательный публичный домен |
| `PUBLIC_PORT` | `443` | Публичный порт |
| `INTERNAL_PORT` | `8888` | Внутренний порт official MTProxy |
| `WORKERS` | `1` | Количество воркеров official MTProxy |
| `ENGINE` | `official` | `official` или `stealth` |
| `PRIMARY_PROFILE` | engine-specific | Базовый профиль bundle |
| `LINK_STRATEGY` | `bundle` | `bundle` или `per-device` |
| `DEVICE_NAMES` | — | Список устройств через запятую для `LINK_STRATEGY=per-device` |
| `TLS_DOMAIN` | `PUBLIC_DOMAIN` | Fake-TLS / SNI domain для `ENGINE=stealth` |
| `DECOY_MODE` | `disabled` | `disabled`, `upstream-forward` или `local-https` |
| `DECOY_TARGET_HOST` | — | Upstream target host для `DECOY_MODE=upstream-forward` |
| `DECOY_TARGET_PORT` | `443` | Upstream target port для `DECOY_MODE=upstream-forward` |
| `DECOY_DOMAIN` | `TLS_DOMAIN` | Домен сертификата и local HTTPS decoy для `DECOY_MODE=local-https` |
| `DECOY_LOCAL_PORT` | `10443` | Loopback port local HTTPS decoy |
| `DECOY_CERT_PATH` | — | Путь к готовому certificate для `DECOY_MODE=local-https` |
| `DECOY_KEY_PATH` | — | Путь к готовому private key для `DECOY_MODE=local-https` |
| `OFFICIAL_REPO_URL` | `https://github.com/TelegramMessenger/MTProxy.git` | Репозиторий official MTProxy |
| `OFFICIAL_REPO_BRANCH` | `master` | Ветка official MTProxy |
| `STEALTH_REPO_URL` | `https://github.com/telemt/telemt.git` | Репозиторий telemt |
| `STEALTH_REPO_BRANCH` | `main` | Ветка telemt |

### Проверка local decoy

Для `DECOY_MODE=local-https` `health` дополнительно проверяет:

- состояние `mtproxy-decoy.service`;
- loopback listener на `127.0.0.1:$DECOY_LOCAL_PORT`;
- HTTPS probe через `curl -sk --resolve ...`.

Совместимость:

- `PORT` поддержан как alias для `PUBLIC_PORT`;
- `REPO_URL` / `REPO_BRANCH` работают как legacy alias для official engine;
- `rotate-secret` сохранен как alias и ротирует первый link slot.

---

## Структура установки

```text
/usr/local/bin/mtproto-proxy
/usr/local/bin/telemt
/usr/local/libexec/mtproxy-run
/usr/local/libexec/mtproxy-refresh
/etc/mtproxy/config/
/etc/mtproxy/secrets/
/etc/mtproxy/links/
/etc/mtproxy/runtime/
/var/lib/mtproxy/
/etc/systemd/system/mtproxy.service
/etc/systemd/system/mtproxy-refresh.service
/etc/systemd/system/mtproxy-refresh.timer
```

`/etc/mtproxy/runtime/telemt.toml` создается только для `ENGINE=stealth`.

---

## Проверка работы

Порт слушается:

```bash
sudo ss -ltn '( sport = :443 )'
```

Статус:

```bash
sudo bash ./install-mtproxy.sh status
```

Health:

```bash
sudo bash ./install-mtproxy.sh health
```

Таймер обновления для official engine:

```bash
sudo systemctl status mtproxy-refresh.timer --no-pager
```

Логи:

```bash
sudo journalctl -u mtproxy.service -n 100 --no-pager
```

---

## Ограничения текущей итерации

- для `DECOY_MODE=local-https` без `DECOY_CERT_PATH` / `DECOY_KEY_PATH` будет создан self-signed certificate;
- для `DECOY_MODE=upstream-forward` нужен уже существующий HTTPS target;
- one-VPS deployment по-прежнему не защищает от прямой блокировки IP/ASN.

---

## Лицензия

MIT — based on [MTProxy](https://github.com/TelegramMessenger/MTProxy)
