#!/usr/bin/env python3

from argparse import ArgumentParser
from logging import Formatter, getLogger, INFO, Logger, StreamHandler
from pathlib import Path
from typing import List, Optional

import httpx  # pip install httpx


def _get_logger() -> Logger:
    logger = getLogger(__file__)
    stream_handler = StreamHandler()
    stream_handler.setFormatter(
        Formatter('%(asctime)s - [%(levelname)s] - %(message)s'))
    logger.addHandler(stream_handler)
    logger.setLevel(INFO)
    return logger


LOGGER = _get_logger()


def check_output(path: Path) -> bool:
    if not path.exists():
        try:
            path.touch()
        except IOError:
            LOGGER.error('Файл "%s" не удалось создать!', path)
            return False
    if not path.is_file():
        LOGGER.error('Путь "%s" должен быть файлом!', path)
        return False
    try:
        with path.open('a'):
            pass
    except IOError:
        LOGGER.error('Файл "%s" должен открываться на запись!', path)
        return False
    return True


def id_import(username: str) -> Optional[List[str]]:
    headers = {'Accept': 'application/vnd.github.v3+json'}
    with httpx.Client(base_url='https://api.github.com/users/',
                      headers=headers) as client:
        try:
            response = client.get(f'{username}/keys')
        except httpx.HTTPError as error:
            LOGGER.error('Не удалось подключиться к GitHub:\n%s', error)
            return None

    try:
        data = response.json()
    except Exception as error:
        LOGGER.error('Неверный ответ сервера:\n%s', error)
        return None

    if not isinstance(data, list):
        LOGGER.error('Неверный ответ сервера:\n%s', data)
        return None

    return [id_item.get('key') for id_item in data if 'key' in id_item]


def id_save(usernames: List[str], output: Path):
    with output.open('a') as file:
        for username in usernames:
            LOGGER.info('Получение ключей для пользователя %s', username)
            id_data = id_import(username)
            if id_data is None:
                continue
            LOGGER.info('Получено ключей: %s', len(id_data))
            id_data.insert(0, f'\n# {username}')
            file.write('\n'.join(id_data))


def main():
    parser = ArgumentParser()
    parser.add_argument('usernames',
                        metavar='USERNAME',
                        nargs='+',
                        type=str,
                        help='Список пользователей GitHub')

    output = Path('~/.ssh/authorized_keys')
    parser.add_argument(
        '-o',
        '--output',
        metavar='PATH/TO/FILE',
        type=lambda o: Path(o).expanduser().resolve(),
        default=output,
        help=('Файл для записи ключей.'
              f' По-умолчанию: "{output.expanduser().resolve()}"'))

    args = parser.parse_args()

    if not check_output(args.output):
        return None

    id_save(args.usernames, args.output)


if __name__ == '__main__':
    main()
