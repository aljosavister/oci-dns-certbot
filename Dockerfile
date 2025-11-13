FROM python:3.12-slim

ENV PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libffi-dev libssl-dev \
    && pip install certbot dns-lexicon[oci] \
    && apt-get purge -y gcc \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY hooks /opt/certbot/hooks
COPY entrypoint.sh /opt/certbot/entrypoint.sh

RUN chmod +x /opt/certbot/entrypoint.sh /opt/certbot/hooks/*.sh

VOLUME ["/etc/letsencrypt", "/var/lib/letsencrypt", "/var/log/letsencrypt", "/export", "/secrets"]

ENTRYPOINT ["/opt/certbot/entrypoint.sh"]
