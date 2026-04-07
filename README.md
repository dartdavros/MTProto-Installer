# 🦺 MTProxy Auto Deploy (Ubuntu 24.04)

Скрипт для быстрой установки и управления Telegram MTProto Proxy на Ubuntu 24.04.

---

## Возможности

- Установка зависимостей и сборка MTProxy из исходников
- Автоматическая настройка systemd-сервиса
- Безопасная конфигурация прав доступа
- Идемпотентная установка (можно запускать повторно)
- Управление через команды (install, restart, status и др.)

---

## Требования

- Ubuntu 24.04
- Root-доступ
- Открытый TCP-порт (по умолчанию 443)

---

## Установка

Скачай скрипт и сделай его исполняемым:
```
chmod +x install-mtproxy.sh
```
Запусти установку:
```
sudo ./install-mtproxy.sh install
```
Пример с параметрами:
```
sudo PORT=443 WORKERS=2 ./install-mtproxy.sh install
```
---

## Результат

После установки будет выведена ссылка подключения:
```
tg://proxy?server=IP&port=PORT&secret=SECRET
```
Используй её в Telegram для подключения к прокси.

---

## Команды

### Установка / обновление
```
sudo ./install-mtproxy.sh install
```
---

### Обновление конфигов Telegram
```
sudo ./install-mtproxy.sh update-config
```
---

### Ротация secret
```
sudo ./install-mtproxy.sh rotate-secret
```
---

### Перезапуск
```
sudo ./install-mtproxy.sh restart
```
---

### Статус и логи
```
sudo ./install-mtproxy.sh status
```
Или напрямую:
```
systemctl status mtproxy
journalctl -u mtproxy -f
```
---

### Удаление
```
sudo ./install-mtproxy.sh uninstall
```
---

## Конфигурация

Переменные окружения:

| Переменная       | По умолчанию | Описание              |
|------------------|-------------|------------------------|
| PORT             | 443         | Публичный порт         |
| INTERNAL_PORT    | 8888        | Внутренний порт        |
| WORKERS          | 1           | Количество воркеров    |
| REPO_URL         | GitHub      | Репозиторий MTProxy    |
| REPO_BRANCH      | master      | Ветка                  |

---

## Структура установки
```
/usr/local/bin/mtproto-proxy
/etc/mtproxy/
/var/lib/mtproxy/
/etc/systemd/system/mtproxy.service
```
---

## Проверка работы

Порт слушается:
```
ss -ltnp | grep mtproto-proxy
```
Логи:
```
journalctl -u mtproxy -n 100
```
---

## Лицензия
MIT — based on [MTProxy](https://github.com/TelegramMessenger/MTProxy)
