# Развёртывание mediamtx-ui в production

Целевая платформа: **Ubuntu 22.04 / 24.04 LTS x64**

---

## Содержание

1. [Требования](#1-требования)
2. [Клонирование проекта](#2-клонирование-проекта)
3. [Автоматическая установка через setup.sh](#3-автоматическая-установка-через-setupsh)
4. [Ручная установка по шагам](#4-ручная-установка-по-шагам)
5. [Настройка конфигурации](#5-настройка-конфигурации)
6. [Генерация пароля и настройка авторизации](#6-генерация-пароля-и-настройка-авторизации)
7. [Запуск сервисов](#7-запуск-сервисов)
8. [Проверка работоспособности](#8-проверка-работоспособности)
9. [Управление сервисами](#9-управление-сервисами)
10. [Настройка firewall](#10-настройка-firewall)
11. [Обновление проекта](#11-обновление-проекта)
12. [Диагностика проблем](#12-диагностика-проблем)

---

## 1. Требования

| Компонент | Минимум | Рекомендуется |
|-----------|---------|---------------|
| ОС | Ubuntu 22.04 LTS x64 | Ubuntu 24.04 LTS x64 |
| CPU | 2 ядра | 4 ядра |
| RAM | 2 GB | 4 GB |
| Диск | 10 GB | 40 GB (для записи видео) |
| Docker | 24.0+ | последний |
| Docker Compose | v2.0+ | последний |

---


 Конфиг mediaMTX находится здесь:

  /var/www/mediamtx-ui/config/mediamtx.yml

  Он монтируется в контейнер как read-only (из docker-compose.yml):
  volumes:
    - ./config/mediamtx.yml:/mediamtx.yml:ro

  Редактировать нужно на хосте, а не внутри контейнера:
  nano /var/www/mediamtx-ui/config/mediamtx.yml

  После изменений — перезапустить mediamtx контейнер:
  docker compose restart mediamtx



## 2. Клонирование проекта

```bash
# Установить git если не установлен
sudo apt-get install -y git

# Клонировать репозиторий
git clone <URL_РЕПОЗИТОРИЯ> /opt/mediamtx-ui

# Перейти в папку проекта
cd /opt/mediamtx-ui
```

---

## 3. Автоматическая установка через setup.sh

Скрипт `setup.sh` выполняет все шаги автоматически: устанавливает Docker, создаёт конфиги, собирает образы.

```bash
cd /opt/mediamtx-ui
sudo bash setup.sh
```

Скрипт выполняет:
- Проверку ОС
- Установку Docker и Docker Compose plugin
- Установку ffmpeg
- Создание файлов конфигурации из шаблонов (`.env`, `config/mediamtx.yml`, `config/auth.json`)
- Создание папок `data/` и `media/`
- Сборку Docker-образов

После успешного завершения перейти к шагу [6. Генерация пароля](#6-генерация-пароля-и-настройка-авторизации).

> Если хотите выполнить установку вручную — читайте раздел 4.

---

## 4. Ручная установка по шагам

### 4.1 Установка Docker

```bash
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sudo sh /tmp/get-docker.sh
rm /tmp/get-docker.sh

# Добавить текущего пользователя в группу docker
sudo usermod -aG docker $USER

# Применить изменения группы (или перелогиниться)
newgrp docker

# Проверить
docker --version
docker compose version
```

### 4.2 Установка ffmpeg

```bash
sudo apt-get install -y ffmpeg
ffmpeg -version
```

### 4.3 Создание конфигурационных файлов

```bash
cd /opt/mediamtx-ui

# Переменные окружения
cp .env.default .env

# Конфиг mediaMTX
cp config/mediamtx.default.yml config/mediamtx.yml

# Конфиг авторизации UI
cp config/auth.default.json config/auth.json

# Создать папки для данных и медиафайлов
mkdir -p data media

# Создать файл данных для первой камеры
echo '{}' > data/cam1.json
```

### 4.4 Сборка Docker-образов

```bash
docker compose build --no-cache
```

---

## 5. Настройка конфигурации

### 5.1 Файл `.env`

Основные параметры проекта:

```bash
nano /opt/mediamtx-ui/.env
```

```env
PROJECT_NAME=mediamtxui
MEDIAMTX_VERSION=1.16.0-ffmpeg-rpi  # версия mediaMTX

SERVER_PORT=3000        # порт Web UI

RTSP_HOST=mediamtx
RTSP_PORT=8554          # RTSP-потоки
RTMP_PORT=1935          # RTMP-потоки
HLS_PORT=8888           # HLS-потоки
WEBRTC_PORT=8889        # WebRTC сигналинг
WEBRTC_UDP_PORT=8189    # WebRTC ICE/UDP
API_PORT=9997           # mediaMTX HTTP API (только внутри docker сети)
METRICS_PORT=9998       # метрики
```

> Порт `API_PORT=9997` **не открывайте** на внешний интерфейс — он используется только внутри Docker-сети.

### 5.2 Файл `config/mediamtx.yml`

Конфигурация mediaMTX — потоки и протоколы:

```bash
nano /opt/mediamtx-ui/config/mediamtx.yml
```

Пример минимальной конфигурации для production:

```yaml
# Протоколы
rtsp: yes
webrtc: yes
hls: yes

# Укажите реальный IP или hostname сервера для WebRTC
webrtcAdditionalHosts: [192.168.1.100]

# Потоки (paths)
paths:
  cam1:
    source: rtsp://USER:PASS@192.168.1.200:554/stream
    sourceOnDemand: yes

  cam2:
    source: publisher
```

Замените:
- `webrtcAdditionalHosts` — на публичный IP или hostname вашего сервера
- `source` в cam1 — на реальный RTSP-адрес вашей камеры

---

## 6. Генерация пароля и настройка авторизации

### 6.1 Сгенерировать хэш пароля

```bash
cd /opt/mediamtx-ui
docker compose run --rm mediamtxui node generate_auth.js
```

Скрипт запросит новый пароль и выведет argon2-хэш. Скопируйте его.

### 6.2 Записать хэш в конфиг

```bash
nano /opt/mediamtx-ui/config/auth.json
```

```json
{
  "username": "admin",
  "password": "$argon2id$v=19$m=65536,t=3,p=4$..."
}
```

Замените значение `"password"` на сгенерированный хэш. Логин можно изменить в поле `"username"`.

> **Внимание:** Никогда не оставляйте пароль по умолчанию в production!

---

## 7. Запуск сервисов

```bash
cd /opt/mediamtx-ui

# Запустить все сервисы в фоне
docker compose up -d
```

Запускаются три сервиса:
- **mediamtx** — сервер медиапотоков
- **mediamtxui** — Web UI управления
- **browser** — вспомогательный headless-браузер

### Автозапуск при перезагрузке сервера

Docker-сервисы с `restart: always` / `restart: unless-stopped` запускаются автоматически при старте системы, если запущен Docker daemon:

```bash
sudo systemctl enable docker
```

---

## 8. Проверка работоспособности

```bash
# Статус контейнеров (все должны быть Up)
docker compose ps

# Проверить, что UI отвечает
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
# Ожидаемый ответ: 200 или 302

# Проверить, что mediaMTX API отвечает
curl -s http://localhost:9997/v3/config/global/get | head -c 200
```

Открыть в браузере:

```
http://<IP_СЕРВЕРА>:3000
```

Войти с логином и паролем из `config/auth.json`.

---

## 9. Управление сервисами

```bash
# Просмотр логов всех сервисов
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f mediamtx
docker compose logs -f mediamtxui

# Остановить все сервисы
docker compose down

# Перезапустить один сервис
docker compose restart mediamtxui

# Войти в контейнер UI для отладки
docker exec -it mediamtxui sh
```

---

## 10. Настройка firewall

Открыть только необходимые порты:

```bash
# Web UI
sudo ufw allow 3000/tcp

# RTSP (если нужен внешний доступ к потокам)
sudo ufw allow 8554/tcp

# RTMP (если нужен внешний доступ)
sudo ufw allow 1935/tcp

# HLS (если нужен внешний доступ)
sudo ufw allow 8888/tcp

# WebRTC
sudo ufw allow 8889/tcp
sudo ufw allow 8189/udp

# SSH (не забудьте!)
sudo ufw allow 22/tcp

# Включить firewall
sudo ufw enable
sudo ufw status
```

> Порты `9997` (API) и `9998` (Metrics) **не открывать** — они доступны только внутри Docker-сети.

---

## 11. Обновление проекта

```bash
cd /opt/mediamtx-ui

# Остановить сервисы
docker compose down

# Получить обновления
git pull

# Пересобрать образы
docker compose build --no-cache

# Запустить снова
docker compose up -d
```

Конфиги (`.env`, `config/mediamtx.yml`, `config/auth.json`) при обновлении **не затрагиваются** — они не входят в git.

---

## 12. Диагностика проблем

### Контейнер не стартует

```bash
docker compose logs mediamtxui
docker compose logs mediamtx
```

### UI недоступен по порту 3000

```bash
# Проверить, слушает ли порт
ss -tlnp | grep 3000

# Проверить статус контейнера
docker compose ps
```

### mediaMTX API не отвечает

```bash
# Проверить доступность внутри docker-сети
docker exec mediamtxui curl -s http://mediamtx:9997/v3/config/global/get
```

### Потоки не воспроизводятся

```bash
# Проверить пути (paths) в mediaMTX
curl -s http://localhost:9997/v3/paths/list

# Проверить доступность камеры
docker exec mediamtxui ffprobe rtsp://USER:PASS@CAMERA_IP:554/stream
```

### Пересоздать контейнеры с нуля

```bash
docker compose down --volumes
docker compose build --no-cache
docker compose up -d
```
