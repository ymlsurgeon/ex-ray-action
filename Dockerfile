FROM python:3.12-slim

# Install dev-trust-scanner directly from GitHub
# TODO: Switch to `pip install dev-trust-scanner` once published to PyPI
RUN pip install --no-cache-dir \
    git+https://github.com/ymlsurgeon/dev-trust-scanner.git@main

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
