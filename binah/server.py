"""Run Binah: the API and web app on the configured hosts, plus the grading queue."""
import logging
import socket

import uvicorn

from . import config
from .app import app, startup


def _bind(host, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((host, port))
    return s


def main():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(name)s %(message)s')
    sockets = [_bind(h, config.PORT) for h in config.HOSTS]
    startup()
    server = uvicorn.Server(uvicorn.Config(app, log_level='info', proxy_headers=False, access_log=False))
    server.run(sockets=sockets)


if __name__ == '__main__':
    main()
