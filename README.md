# 🦺 MTProxy Private Deploy (Ubuntu 24.04)

Скрипт для установки и управления **private MTProto proxy** на Ubuntu 24.04.

Текущая реализация переводит установку на доменно-обязательный контракт и quiet-by-default модель:

- `PUBLIC_DOMAIN` обязателен при первой установке;
- ссылки и secret не печатаются по умолчанию;
- создается bundle из нескольких ссылок;
- есть manifest, link slots, ротация ссылок и daily refresh Telegram config.

> В этой итерации поддержан только `ENGINE=official`.
> `ENGINE=stealth` пока не реализован и завершится с явной ошибкой.

---

## Возможности

- установка зависимостей и сборка official MTProxy из исходников;
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
- автоматический daily refresh `proxy-multi.conf` через systemd timer;
- health/status команды без штатной печати secret.

---

## Требования

- Ubuntu 24.04
- Root-доступ
- Домен, указывающий на VPS
- Открытый TCP-порт (по умолчанию `443`)

---

## Установка

### Быстрый запуск

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh | \
  sudo PUBLIC_DOMAIN=proxy.example.com bash -s -- install
```

### Надежный вариант в 2 шага

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh install
```

Пример с параметрами:

```bash
sudo PUBLIC_DOMAIN=proxy.example.com PUBLIC_PORT=443 WORKERS=2 bash ./install-mtproxy.sh install
```

---

## Поведение после установки

После установки скрипт выводит только безопасную сводку:

- домен;
- порт;
- engine;
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

## Команды

### Установка / обновление структуры

```bash
sudo PUBLIC_DOMAIN=proxy.example.com bash ./install-mtproxy.sh install
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
| `INTERNAL_PORT` | `8888` | Внутренний порт MTProxy |
| `WORKERS` | `1` | Количество воркеров |
| `ENGINE` | `official` | Текущий runtime engine |
| `PRIMARY_PROFILE` | `dd` | Базовый профиль bundle (`dd` или `classic`) |
| `LINK_STRATEGY` | `bundle` | Стратегия выдачи ссылок |
| `REPO_URL` | `https://github.com/TelegramMessenger/MTProxy.git` | Репозиторий MTProxy |
| `REPO_BRANCH` | `master` | Ветка |

Совместимость:

- `PORT` поддержан как alias для `PUBLIC_PORT`;
- `rotate-secret` сохранен как alias и ротирует первый link slot.

---

## Структура установки

```text
/usr/local/bin/mtproto-proxy
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

---

## Проверка работы

Порт слушается:

```bash
sudo ss -ltn '( sport = :443 )'
```

Таймер обновления:

```bash
sudo systemctl status mtproxy-refresh.timer --no-pager
```

Логи:

```bash
sudo journalctl -u mtproxy.service -n 100 --no-pager
```

---

## Ограничения текущей итерации

- stealth engine пока не интегрирован;
- `ee` / Fake TLS и decoy contour пока не реализованы;
- `per-device` strategy пока не реализована.

То есть сейчас закрыта безопасная foundation-итерация для official runtime: install contract, artifact model, multi-link management и automated refresh.

---

## Лицензия

MIT — based on [MTProxy](https://github.com/TelegramMessenger/MTProxy)
