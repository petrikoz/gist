#!/usr/bin/env python3

from pathlib import Path
import argparse
import configparser
import os
import signal
import tarfile

import httpx  # pip install httpx
import psutil  # pip install psutil

BASE_DIR = Path(__file__).parent


def get_config(path):
    path = Path(path)

    config = configparser.ConfigParser()
    config.read(path)
    print(f'Используем конфиг: {path.absolute()}')
    return config['API']


def download_certs(client, certs, archive_path, archive_type):
    _certs = {}
    _archive_path = Path(archive_path)
    for domain, cert_id in certs.items():
        archive = _archive_path.joinpath(f'{domain}.{archive_type}')
        with archive.open('wb') as archive_file:
            url = f'{cert_id}/download/'
            params = {'name': domain, 'type': archive_type}
            with client.stream('GET', url, params=params) as response:
                for data in response.iter_bytes():
                    archive_file.write(data)

        _certs[domain] = archive
        print(f'Домен {domain}: сертификат скачан в {archive}')

    return _certs


def get_token(api_key):
    with httpx.Client() as client:
        response = client.post('https://panel.netangels.ru/api/gateway/token/',
                               data={'api_key': api_key})
    return response.json()['token']


def get_certs(client, domains):
    certs = {}
    for domain in domains:
        response = client.get('find/',
                              params={
                                  'domains': domain,
                                  'is_issued_only': True
                              })
        data = response.json()
        for entity in data['entities']:
            if domain in entity['domains']:
                cert_id = entity['id']
                certs[domain] = cert_id
                print(f'Домен {domain}: ID сертификата {cert_id}')
                break
    return certs


def reload_nginx():
    process = None
    for proc in psutil.process_iter(attrs=['pid', 'name', 'cmdline']):
        cmdline = [
            part.strip().lower()
            for part in proc.cmdline()
            if part.strip().lower() not in (None, '')
        ]
        if 'nginx' == proc.name().lower():
            # если нашли мастера, то берём его и выходим из цикла
            if 'master' in cmdline:
                process = proc
                break
            # берём первый процесс на случай, если не найдём мастера
            if process is None:
                process = proc

    if process is None:
        print('Не найден процесс Nginx')
        return

    os.kill(process.pid, signal.SIGHUP)
    print('Обновлена конфигурация Nginx')


def renew_certs(certs, nginx_ssl):
    for domain, archive in certs.items():
        path = Path(nginx_ssl).joinpath(domain)
        path.mkdir(parents=True, exist_ok=True)

        tar = tarfile.open(archive)
        tar.extractall(path=path)
        tar.close()
        print(f'Домен {domain}: сертификаты распакованы в {path}')


def main(config_path):
    config = get_config(config_path)

    token = get_token(config['api_key'])
    print('Получили токен')

    with httpx.Client(
            headers={'Authorization': f'Bearer {token}'},
            base_url='https://api-ms.netangels.ru/api/v1/certificates/'
    ) as client:
        certs = get_certs(client, config['domains'].split(','))
        certs = download_certs(client, certs, config['archive_path'],
                               config['archive_type'])
    renew_certs(certs, config['nginx_ssl'])
    reload_nginx()


if __name__ == '__main__':

    parser = argparse.ArgumentParser()

    default = BASE_DIR.joinpath('config.ini')
    parser.add_argument('-c',
                        '--config',
                        default=default,
                        help=f'Config path. Default: "{default.absolute()}"')

    args = parser.parse_args()
    main(args.config)
