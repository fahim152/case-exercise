FROM kong:3.9.4
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /var/lib/lab-secrets && chown kong:kong /var/lib/lab-secrets && chmod 700 /var/lib/lab-secrets
COPY bootstrap.sh /opt/lab/bootstrap.sh
COPY entrypoint.sh /opt/lab/entrypoint.sh
RUN chmod 755 /opt/lab/entrypoint.sh /opt/lab/bootstrap.sh
USER kong
ENTRYPOINT ["/opt/lab/entrypoint.sh"]
CMD ["kong", "docker-start"]
