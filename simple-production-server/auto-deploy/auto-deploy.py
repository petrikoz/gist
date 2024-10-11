#!/usr/bin/env python3
#
# Copyright 2024 ITCase (info@itcase.pro)

from email.message import EmailMessage
from pathlib import Path
import argparse
import configparser
import logging
import smtplib

import invoke  # pip install invoke

FILE = Path(__file__)
BASE_DIR = FILE.parent


# ****************************************************************
# GIT


GITHUB_ERRORS_SKIP = ("closed by remote host", "Connection reset", "net/http")


def _git_get_branch(context: invoke.context.Context, remote: str):
    branch = context.run("git rev-parse --abbrev-ref HEAD").stdout.strip()
    res = context.run(f"git fetch -q {remote} {branch}", warn=True)
    if res.exited != 0:
        if any(error in res.stderr for error in GITHUB_ERRORS_SKIP):
            _log(f"Проблемы с сетью:{res.stderr}", "error")
            return
        raise invoke.exceptions.UnexpectedExit(res)
    updates_count = int(context.run(f"git rev-list --count {remote}/{branch}...{branch}").stdout.strip())
    if updates_count < 1:
        _log("Нет изменений в GIT-репозитории")
        return
    return branch


# ****************************************************************
# LOG


LOGGER = logging.getLogger(FILE.stem)


def _configure_logger(log_file, log_debug):
    handler = logging.FileHandler(log_file, "w")
    handler.setFormatter(logging.Formatter("%(asctime)s    %(levelname)s    %(message)s"))
    LOGGER.addHandler(handler)
    LOGGER.setLevel(logging.DEBUG if log_debug else logging.INFO)


def _log(message: str, method="info"):
    getattr(LOGGER, method)(message)


def _log_exit(message: str, method="info", code=0):
    _log(message, method)
    exit(code)


# ****************************************************************
# NEXTJS


def deploy_django(context: invoke.context.Context, config: dict):
    _log("Django-код: обновляем...")
    git_branch = None
    with context.cd(config["PATH"]):
        git_remote = config.get("GIT_REMOTE", "origin")
        git_branch = _git_get_branch(context, git_remote)
        if git_branch is None:
            return
        _log("Получаем изменения")
        context.run(f"git pull {git_remote} {git_branch}")

        poetry = config["POETRY"]
        _log("Устанавливаем зависимости")
        context.run(f"{poetry} install --no-root --without=dev,itcase,test")

        venv_python = config["VENV_PYTHON"]
        _log("Накатываем миграции на БД")
        context.run(f"{venv_python} manage.py migrate")
        _log("Копируем статику")
        context.run(f"{venv_python} manage.py collectstatic --noinput")

        _log("Перезагружаем uWSGI")
        Path(config["UWSGI_TOUCH"]).touch()

    _log("Django-код: готово!")
    return bool(git_branch is not None)


# ****************************************************************
# NEXTJS


def deploy_nextjs(context: invoke.context.Context, config: dict):
    _log("NextJS-код: обновляем...")

    _log(f"Авторизуемся в {config['GHCR_SERVER']}")
    res = context.run(
        f"echo {config['GHCR_TOKEN']}"
        f" | docker login {config['GHCR_SERVER']} --username {config['GHCR_USERNAME']} --password-stdin",
        warn=True,
    )
    if res.exited != 0:
        if any(error in res.stderr for error in GITHUB_ERRORS_SKIP):
            _log(f"Проблемы с сетью:{res.stderr}", "error")
            return
        raise invoke.exceptions.UnexpectedExit(res)

    docker_image = (
        f"{config['GHCR_SERVER']}/{config['GHCR_NAMESPACE']}/{config['GHCR_IMAGE_NAME']}:{config['GHCR_IMAGE_TAG']}"
    ).lower()

    docker_image_digest = ""
    res = context.run("docker inspect --format='{{index .RepoDigests 0}}' %s" % docker_image, warn=True)
    if res.exited == 0:
        try:
            docker_image_digest = res.stdout.split("@")[1]
        except Exception:
            pass

    _log(f"Получаем Docker-образ {docker_image}")
    res = context.run(f"docker image pull {docker_image}", warn=True)
    if res.exited != 0:
        if "manifest unknown" in res.stderr:
            _log(f"Нет обновлений Docker-образа {docker_image}")
            return
        if any(error in res.stderr for error in GITHUB_ERRORS_SKIP):
            _log(f"Проблемы с сетью:{res.stderr}", "error")
            return
        raise invoke.exceptions.UnexpectedExit(res)
    if docker_image_digest and docker_image_digest in str(res.stdout):
        _log(f"Нет обновлений Docker-образа {docker_image}")
        return

    _log(f"Останавливаем старый Docker-контейнер {config['DOCKER_CONTAINER_NAME']}")
    context.run(f"docker rm --force {config['DOCKER_CONTAINER_NAME']}")

    _log(
        f"Запускаем обновлённый Docker-контейнер {config['DOCKER_CONTAINER_NAME']}"
        f" на порту {config['DOCKER_CONTAINER_HOST_PORT']}"
    )
    context.run(
        f"docker run -d -p 127.0.0.1:{config['DOCKER_CONTAINER_HOST_PORT']}:3000"
        f" --name={config['DOCKER_CONTAINER_NAME']} --restart=always --quiet {docker_image}"
    )

    _log("Удаляем ненужные Docker-образы")
    context.run("docker image prune --force", warn=True)

    _log("NextJS-код: готово!")
    return True


# ****************************************************************
# STORYBOOK


def deploy_storybook(context: invoke.context.Context, config: dict):
    _log("StoryBook: собираем...")
    git_branch = None
    with context.cd(config["PATH"]):
        git_remote = config.get("GIT_REMOTE", "origin")
        git_branch = _git_get_branch(context, git_remote)
        if git_branch is None:
            return
        _log("Чистим локальные изменения")
        context.run("git reset --hard && git clean -fd")
        _log("Получаем изменения")
        context.run(f"git pull {git_remote} {git_branch}")
        _log("Устанавливаем зависимости")
        context.run("npm install --force")
        _log("Чистим файловый кэш NodeJS")
        context.run("rm -rf node_modules/.cache")
        _log("Собираем обновлённый код")
        context.run(f"npx --yes storybook build --output-dir {config['OUTPUT']}")
    _log("StoryBook: готово!")
    return bool(git_branch is not None)


# ****************************************************************
# MAIN


def _get_config(path: str):
    _path = Path(path)
    config = configparser.ConfigParser()
    config.read(_path)
    _log(f"Используем конфиг: {_path.absolute()}")
    return config


def _send_email(config: dict, subject: str, body: str):
    _log("Подключаемся к SMTP-серверу", "debug")
    server = smtplib.SMTP(config["HOST"], config["PORT"])

    if config.get("USE_TLS", False):
        _log("Устанавливаем TLS-соединение", "debug")
        server.ehlo()
        server.starttls()

    _log("Авторизуемся", "debug")
    server.login(config["USER"], config["PASSWORD"])

    _log("Создаём сообщение", "debug")
    msg = EmailMessage()
    msg.set_content(body)
    msg["From"] = config["USER"]
    msg["Subject"] = subject

    for recipient in str(config["RECIPIENTS"]).split(","):
        recipient = recipient.strip()
        _log(f'Отправка сообщения на "{recipient}"')
        msg["To"] = recipient
        try:
            server.send_message(msg)
        except Exception as e:
            _log(str(e), "error")
        del msg["To"]

    _log("Отключаемся от сервера", "debug")
    server.quit()


def _send_email_fail(config: dict, body: str):
    return _send_email(config, f'Проблемы с деплоем проекта {config["PROJECT"]}', body)


def _send_email_success(config: dict, body: str):
    return _send_email(config, f'Успешный деплой проекта {config["PROJECT"]}', body)


LOCK_FILE = BASE_DIR / "lock"


def main(args):
    log_file = Path(args.log)

    try:
        LOCK_FILE.touch()

        context = invoke.context.Context(invoke.config.Config(overrides={"run": {"hide": "both"}}))

        config = _get_config(args.config)
        result_django = deploy_django(context, config["DJANGO"])
        result_nextjs = deploy_nextjs(context, config["NEXTJS"])
        try:
            deploy_storybook(context, config["STORYBOOK"])
        except Exception as e:
            _log(str(e), "error")
    except Exception as e:
        _log(str(e), "error")
        try:
            _log("Отправка письма с ошибками", "debug")
            _send_email_fail(config["EMAIL"], log_file.read_text())
        except Exception as e:
            _log_exit(str(e), "error", 1)
        exit(1)
    else:
        LOCK_FILE.unlink(missing_ok=True)

    if result_django or result_nextjs:
        _log("Отправка письма об успешном деплое", "debug")
        _send_email_success(config["EMAIL"], log_file.read_text())


DEFAULT_CONFIG_FILE = (BASE_DIR / "config.ini").absolute()
DEFAULT_LOG_FILE = (BASE_DIR / f"{FILE.stem}.log").absolute()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-c", "--config", default=DEFAULT_CONFIG_FILE, help=f'Путь к конфигу. По-умолчанию: "{DEFAULT_CONFIG_FILE}"'
    )
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument(
        "-l", "--log", default=DEFAULT_LOG_FILE, help=f'Путь к файлу лога. По-умолчанию: "{DEFAULT_LOG_FILE}"'
    )

    args = parser.parse_args()

    if LOCK_FILE.exists():
        _log_exit("Процесс выполняется или завершился с ошибкой", "warning")

    _configure_logger(args.log, args.debug)

    main(args)
