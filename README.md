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
- для stealth engine есть реальный runtime adapter, `TLS_DOMAIN` и optional upstream decoy forwarding.

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
- quiet-by-default install/status;
- ротация одной ссылки или всех ссылок;
- engine-aware secret storage и link rendering;
- автоматический daily refresh `proxy-multi.conf` через systemd timer для `ENGINE=official`;
- stealth runtime через `telemt` для `ENGINE=stealth`.

---

## Требования

- Ubuntu 24.04
- Root-доступ
- Домен, указывающий на VPS
- Открытый TCP-порт (по умолчанию `443`)

Для `ENGINE=stealth`:

- если используется `DECOY_MODE=upstream-forward`, нужен реальный upstream HTTPS target.

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

---

## Поведение после установки

После установки скрипт выводит только безопасную сводку:

- домен;
- порт;
- engine;
- TLS domain;
- decoy mode;
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
| `LINK_STRATEGY` | `bundle` | Стратегия выдачи ссылок |
| `TLS_DOMAIN` | `PUBLIC_DOMAIN` | Fake-TLS / SNI domain для `ENGINE=stealth` |
| `DECOY_MODE` | `disabled` | `disabled` или `upstream-forward` |
| `DECOY_TARGET_HOST` | — | Upstream target host для decoy |
| `DECOY_TARGET_PORT` | `443` | Upstream target port для decoy |
| `OFFICIAL_REPO_URL` | `https://github.com/TelegramMessenger/MTProxy.git` | Репозиторий official MTProxy |
| `OFFICIAL_REPO_BRANCH` | `master` | Ветка official MTProxy |
| `STEALTH_REPO_URL` | `https://github.com/telemt/telemt.git` | Репозиторий telemt |
| `STEALTH_REPO_BRANCH` | `main` | Ветка telemt |

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

- `LINK_STRATEGY=per-device` пока не реализован;
- `DECOY_MODE=local-https` пока не реализован;
- автоматический decoy deployment не делается — для `upstream-forward` нужен уже существующий HTTPS target;
- one-VPS deployment по-прежнему не защищает от прямой блокировки IP/ASN.

---

## Лицензия

MIT — based on [MTProxy](https://github.com/TelegramMessenger/MTProxy)
