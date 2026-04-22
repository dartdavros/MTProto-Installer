# 🦺 MTProxy Installer

Скрипт для установки и управления Telegram MTProto Proxy на Ubuntu 24.04.  
Поддерживает stealth-режим и decoy-контур.

## 📋 Что нужно перед установкой

- **VPS на Ubuntu 24.04**  
  Скрипт рассчитан именно на эту систему.

- **Root-доступ**  
  Нужен для установки пакетов, настройки systemd, firewall и системных файлов.

- **Основной домен**  
  Он нужен для клиентских ссылок и основной точки подключения прокси.  
  Пример: `mtp.example.com`

- **Второй домен, если ты планируешь использовать decoy**  
  Он нужен только для decoy-сценария. Если decoy не используешь, второй домен не нужен.  
  Пример: `cdn.example.com`

- **Открытый публичный TCP-порт**  
  Основной внешний вход — `443/tcp`.

- **DNS-записи доменов должны указывать на твой VPS**  
  Иначе клиентские ссылки и проверка домена будут работать некорректно.

## 📦 Установка

Скачай скрипт:

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh
```

Запусти скрипт:

```bash
sudo bash ./install-mtproxy.sh
```

Если рядом нет полного репозитория, bootstrap-скрипт сам подтянет полный installer runtime и сохранит его в `/opt/mtproxy-installer/current`, после чего продолжит установку уже из постоянного каталога.

Дальше следуй шагам интерактивного режима.

## 🔗 На выходе получаете

После установки будет настроен сервис прокси и подготовлен набор клиентских ссылок.

По умолчанию ссылки и секреты не показываются в обычном выводе.  
Чтобы получить ссылки явно, используй команду `share-links`.

## ⚙️ Команды

**Установка:**

```bash
sudo bash ./install-mtproxy.sh install
```

**Статус:**

```bash
sudo bash ./install-mtproxy.sh status
```

**Проверка состояния:**

```bash
sudo bash ./install-mtproxy.sh health
```

**Показать ссылки подключения:**

```bash
sudo bash ./install-mtproxy.sh share-links
```

**Показать список ссылок без секретов:**

```bash
sudo bash ./install-mtproxy.sh list-links
```

**Ротация одной ссылки:**

```bash
sudo bash ./install-mtproxy.sh rotate-link <name>
```

**Ротация всех ссылок:**

```bash
sudo bash ./install-mtproxy.sh rotate-all-links
```

**Обновление конфигов Telegram:**

```bash
sudo bash ./install-mtproxy.sh refresh-telegram-config
```

**Перезапуск:**

```bash
sudo bash ./install-mtproxy.sh restart
```

**Проверка домена:**

```bash
sudo bash ./install-mtproxy.sh check-domain
```

**Проверка decoy-контура:**

```bash
sudo bash ./install-mtproxy.sh test-decoy
```

**Удаление:**

```bash
sudo bash ./install-mtproxy.sh uninstall
```

## 🔍 Проверка работы

**Статус сервиса:**

```bash
sudo bash ./install-mtproxy.sh status
```

**Расширенная проверка:**

```bash
sudo bash ./install-mtproxy.sh health
```

**Логи:**

```bash
sudo journalctl -u mtproxy -n 100 --no-pager
```

**Или в live-режиме:**

```bash
sudo journalctl -u mtproxy -f
```

## 🔄 Как обновить

Скачай актуальную версию скрипта поверх старой:

```bash
curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh
```

После этого снова запусти:

```bash
sudo bash ./install-mtproxy.sh
```

Если файл скачан отдельно, он обновит bootstrap-runtime и снова передаст выполнение в постоянный installer runtime.

Дальше выбери нужное действие в интерактивном режиме.

## 🗑 Как удалить

Для удаления используй:

```bash
sudo bash ./install-mtproxy.sh uninstall
```

## 📄 Лицензия

MIT — based on MTProxy
