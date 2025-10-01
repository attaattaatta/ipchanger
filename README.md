# ipchanger
bash ip changer

Скрипт для автоматической замены IP-адреса (самое частое, но, можно, что угодно на что угодно заменить) на сервере с поддержкой **ISPmanager** и системных конфигураций.

## Запуск:
```
bash <(wget --no-check-certificate -q -o /dev/null -O- https://bit.ly/3uSpUrM) old_ip new_ip <old_gateway> <new_gateway>
```
```
bash <(curl -kLs https://bit.ly/3uSpUrM) old_ip new_ip <old_gateway> <new_gateway>
```

## Возможности
- Проверка root-доступа и аргументов
- Валидация IPv4
- Резервные копии сетевых конфигов и БД ISPmanager
- Замена IP в:
  - `/etc`, `/var/named`, `/var/lib/powerdns`, Docker, Netplan, NetworkManager
- Обновление PowerDNS и ISPmanager (SQLite/MySQL)
- Очистка кеша и перезапуск ISPmanager
- Поддержка смены шлюза (опционально, маску меняем руками)
