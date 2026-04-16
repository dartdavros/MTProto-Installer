# 🦺 MTProxy Auto Deploy (Ubuntu 24.04)

Скрипт для быстрой установки и управления Telegram MTProto Proxy на Ubuntu 24.04.

---

## Возможности

- Установка зависимостей и сборка MTProxy из исходников
- Автоматическая настройка systemd-сервиса
- Безопасная конфигурация прав доступа
- Идемпотентная установка (можно запускать повторно)
- Управление через команды (`install`, `restart`, `status` и др.)

---

## Требования

- Ubuntu 24.04
- Root-доступ
- Открытый TCP-порт (по умолчанию `443`)

---

## Установка

### Быстрый запуск одной командой

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh | sudo bash -s -- install
```

### Надежный вариант в 2 шага

Скачай скрипт:

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh
```

Запусти установку:

```bash
sudo bash ./install-mtproxy.sh install
```

Пример с параметрами:

```bash
sudo PORT=443 WORKERS=2 bash ./install-mtproxy.sh install
```

> Важно: используй именно `raw.githubusercontent.com`, а не GitHub URL вида `.../blob/...`.
> Скрипт рассчитан на запуск через `bash`, не через `sh`.

---

## Результат

После установки будет выведена ссылка подключения:

```text
tg://proxy?server=IP&port=PORT&secret=SECRET
```

Используй её в Telegram для подключения к прокси.

---

## Команды

### Установка / обновление

```bash
sudo bash ./install-mtproxy.sh install
```

### Обновление конфигов Telegram

```bash
sudo bash ./install-mtproxy.sh update-config
```

### Ротация secret

```bash
sudo bash ./install-mtproxy.sh rotate-secret
```

### Перезапуск

```bash
sudo bash ./install-mtproxy.sh restart
```

### Статус и логи

```bash
sudo bash ./install-mtproxy.sh status
```

Или напрямую:

```bash
systemctl status mtproxy
journalctl -u mtproxy -f
```

### Удаление

```bash
sudo bash ./install-mtproxy.sh uninstall
```

---

## Конфигурация

Переменные окружения:

| Переменная | По умолчанию | Описание |
|---|---:|---|
| `PORT` | `443` | Публичный порт |
| `INTERNAL_PORT` | `8888` | Внутренний порт |
| `WORKERS` | `1` | Количество воркеров |
| `REPO_URL` | `https://github.com/TelegramMessenger/MTProxy.git` | Репозиторий MTProxy |
| `REPO_BRANCH` | `master` | Ветка |

---

## Структура установки

```text
/usr/local/bin/mtproto-proxy
/etc/mtproxy/
/var/lib/mtproxy/
/etc/systemd/system/mtproxy.service
```

---

## Проверка работы

Порт слушается:

```bash
sudo ss -ltnp 'sport = :443'
```

Логи:

```bash
sudo journalctl -u mtproxy -n 100 --no-pager
```

Статус сервиса:

```bash
sudo systemctl status mtproxy.service --no-pager -l
```

---

## Лицензия

MIT — based on [MTProxy](https://github.com/TelegramMessenger/MTProxy)
