#!/usr/bin/env python
# Copyright 2022 Petr Zelenin (po.zelenin@itcase.pro)

from argparse import ArgumentParser
from pathlib import Path
from typing import Dict, List
import json


def _error_exit(error: str):
    print(error)
    exit(1)


try:
    import httpx
except ImportError:
    _error_exit('\nInstall HTTPx:\n\tpip install httpx\n')

ERRORS = {
    'wrong_data_in_response': '\nWrong data in response:\n\t%(data)s\n',
    'wrong_data_in_row': '\nWrong data in row %(row_num)s:\n\t%(row)s',
    'wrong_output_path': '\nWrong output path:\n\t%(path)s',
}


def get_rows(data: Dict) -> List:
    table = data.get('table', {})
    rows = table.get('rows', [])
    if not rows:
        _error_exit(ERRORS['wrong_data_in_response'] % {'data': data})
    return rows


def get_spreadsheet_as_json(spreadsheet_id: str) -> Dict:
    url = f'https://docs.google.com/spreadsheets/d/{spreadsheet_id}/gviz/tq'

    response = httpx.get(url)
    data = response.text.splitlines()[-1]

    data_prefix = 'google.visualization.Query.setResponse('
    data_suffix = ');'
    if not data.startswith(data_prefix) and not data.endswith(data_suffix):
        _error_exit(ERRORS['wrong_data_in_response'] % {'data': data})

    data = data[len(data_prefix):-len(data_suffix)]

    try:
        data = json.loads(data)
    except TypeError:
        _error_exit(ERRORS['wrong_data_in_response'] % {'data': data})

    return data


def get_parsed_data(rows: List, value_cell_index: int) -> Dict:
    parsed_data: Dict = {}
    for row_num, row in enumerate(rows, start=1):
        cells = row.get('c', [])
        try:
            key = cells[0]
            value = cells[value_cell_index]
        except IndexError:
            print(ERRORS['wrong_data_in_row'] % {
                'row_num': row_num,
                'row': row,
            })
            continue

        if not hasattr(key, 'get') or not hasattr(value, 'get'):
            continue

        key = key.get('v')
        value = value.get('v')
        if key in (None, '') or value in (None, ''):
            continue

        key_data = parsed_data
        key_parts = key.split('.')
        key_parts_count = len(key_parts)
        for key_part_num, key_part in enumerate(key_parts, start=1):
            default = {} if key_part_num != key_parts_count else value
            key_data = key_data.setdefault(key_part, default)

    return parsed_data


def main():
    # ****************************************************************
    # OPTIONS

    parser = ArgumentParser(
        description='Generate locales from Google SpreadSheet')

    parser.add_argument(dest='spreadsheet_id',
                        type=str,
                        metavar='SPREADSHEET-ID',
                        help='Spreadsheet ID from URL to Google Drive')
    parser.add_argument(type=int,
                        dest='value_cell_index',
                        metavar='LOCALE-COLUMN-INDEX',
                        help='Column index starting from 0')
    parser.add_argument(type=str,
                        dest='output_path',
                        metavar='OUTPUT-FILE-PATH',
                        help='Full path to the file')

    # ****************************************************************

    args = parser.parse_args()

    save_path = Path(args.output_path).resolve()
    if save_path.exists() and not save_path.is_file():
        _error_exit(ERRORS['wrong_output_path'] % {'path': save_path})

    # ****************************************************************
    # PROCESS DATA

    print('Try load data from Google...')
    data = get_spreadsheet_as_json(args.spreadsheet_id)
    rows = get_rows(data)
    print('Data loaded from Google!')

    print('Try parse data...')
    parsed_data = get_parsed_data(rows, args.value_cell_index)
    print('Data parsed!')

    save_path.write_text(json.dumps(parsed_data))
    print(f'Data saved to file:\n\t{save_path}')


if __name__ == '__main__':
    main()
