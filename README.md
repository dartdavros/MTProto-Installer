🦺 MTProxy Installer

Скрипт для установки и управления Telegram MTProto Proxy на Ubuntu 24.04.
Поддерживает stealth-режим и decoy-контур.

📋 Что нужно перед установкой

VPS на Ubuntu 24.04.
Скрипт рассчитан именно на эту систему.

Root-доступ.
Нужен для установки пакетов, настройки systemd, firewall и системных файлов.

Основной домен.
Он нужен для клиентских ссылок и основной точки подключения прокси.
Пример: mtp.example.com

Второй домен, если ты планируешь использовать decoy.
Он нужен только для decoy-сценария. Если decoy не используешь, второй домен не нужен.
Пример: cdn.example.com

Открытый публичный TCP-порт.
Основной внешний вход — 443/tcp.

DNS-записи доменов должны указывать на твой VPS.
Иначе клиентские ссылки и проверка домена будут работать некорректно.

📦 Установка

Скачай скрипт:

curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh

Запусти скрипт:

sudo bash ./install-mtproxy.sh

Дальше следуй шагам интерактивного режима.

🔗 На выходе получаете

После установки будет настроен сервис прокси и подготовлен набор клиентских ссылок.

По умолчанию ссылки и секреты не показываются в обычном выводе.
Чтобы получить ссылки явно, используй команду share-links.

⚙️ Команды

Установка:
sudo bash ./install-mtproxy.sh install

Статус:
sudo bash ./install-mtproxy.sh status

Проверка состояния:
sudo bash ./install-mtproxy.sh health

Показать ссылки подключения:
sudo bash ./install-mtproxy.sh share-links

Показать список ссылок без секретов:
sudo bash ./install-mtproxy.sh list-links

Ротация одной ссылки:
sudo bash ./install-mtproxy.sh rotate-link <name>

Ротация всех ссылок:
sudo bash ./install-mtproxy.sh rotate-all-links

Обновление конфигов Telegram:
sudo bash ./install-mtproxy.sh refresh-telegram-config

Перезапуск:
sudo bash ./install-mtproxy.sh restart

Проверка домена:
sudo bash ./install-mtproxy.sh check-domain

Проверка decoy-контура:
sudo bash ./install-mtproxy.sh test-decoy

Удаление:
sudo bash ./install-mtproxy.sh uninstall

🔍 Проверка работы

Статус сервиса:
sudo bash ./install-mtproxy.sh status

Расширенная проверка:
sudo bash ./install-mtproxy.sh health

Логи:
sudo journalctl -u mtproxy -n 100 --no-pager

Или в live-режиме:
sudo journalctl -u mtproxy -f

🔄 Как обновить

Скачай актуальную версию скрипта поверх старой:

curl -fsSL https://raw.githubusercontent.com/dartdavros/MTProto-Installer/main/install-mtproxy.sh -o install-mtproxy.sh
chmod +x install-mtproxy.sh

После этого снова запусти:

sudo bash ./install-mtproxy.sh

Дальше выбери нужное действие в интерактивном режиме.

🗑 Как удалить

Для удаления используй:

sudo bash ./install-mtproxy.sh uninstall

📄 Лицензия

MIT — based on MTProxy
