# syntax=docker/dockerfile:1
ARG NAGIOS_VERSION=4.5.14
ARG NAGIOS_PLUGINS_VERSION=2.5

########################################
# Stage 1: build Nagios Core + Plugins
########################################
FROM ubuntu:26.04 AS builder
ARG NAGIOS_VERSION
ARG NAGIOS_PLUGINS_VERSION
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        wget ca-certificates \
        build-essential autoconf gettext bc unzip \
        apache2 apache2-utils \
        libgd-dev libssl-dev libperl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 3000 nagios \
    && groupadd -g 3001 nagcmd \
    && useradd -m -u 3000 -g nagios -G nagcmd -s /usr/sbin/nologin nagios \
    && usermod -a -G nagcmd www-data

WORKDIR /usr/src

RUN wget -qO nagios.tar.gz \
        "https://github.com/NagiosEnterprises/nagioscore/releases/download/nagios-${NAGIOS_VERSION}/nagios-${NAGIOS_VERSION}.tar.gz" \
    && tar xzf nagios.tar.gz \
    && rm nagios.tar.gz

RUN wget -qO nagios-plugins.tar.gz \
        "https://github.com/nagios-plugins/nagios-plugins/releases/download/release-${NAGIOS_PLUGINS_VERSION}/nagios-plugins-${NAGIOS_PLUGINS_VERSION}.tar.gz" \
    && tar xzf nagios-plugins.tar.gz \
    && rm nagios-plugins.tar.gz

# --- Build Nagios Core ---
WORKDIR /usr/src/nagios-${NAGIOS_VERSION}
RUN ./configure \
        --with-nagios-group=nagios \
        --with-command-group=nagcmd \
        --with-httpd-conf=/etc/apache2/sites-enabled \
    && make all \
    && make install \
    && make install-init \
    && make install-config \
    && make install-commandmode \
    && make install-webconf

RUN a2enmod cgi rewrite

# --- Build Nagios Plugins ---
WORKDIR /usr/src/nagios-plugins-${NAGIOS_PLUGINS_VERSION}
RUN ./configure \
        --prefix=/usr/local/nagios \
        --with-nagios-user=nagios \
        --with-nagios-group=nagios \
    && make \
    && make install

########################################
# Stage 2: runtime image
########################################
FROM ubuntu:26.04
ARG DEBIAN_FRONTEND=noninteractive
LABEL org.opencontainers.image.title="Nagios Core" \
      org.opencontainers.image.source="https://github.com/NagiosEnterprises/nagioscore"

RUN apt-get update && apt-get install -y --no-install-recommends \
        apache2 apache2-utils php libapache2-mod-php php-gd \
        libgd3 libssl3 perl \
        iputils-ping dnsutils \
        supervisor \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 3000 nagios \
    && groupadd -g 3001 nagcmd \
    && useradd -m -u 3000 -g nagios -G nagcmd -s /usr/sbin/nologin nagios \
    && usermod -a -G nagcmd www-data

COPY --from=builder /usr/local/nagios /usr/local/nagios
COPY --from=builder /etc/init.d/nagios /etc/init.d/nagios
COPY --from=builder /etc/apache2/sites-enabled/nagios.conf /etc/apache2/sites-enabled/nagios.conf

RUN a2enmod cgi rewrite \
    && chown -R nagios:nagcmd /usr/local/nagios \
    && echo "ServerName localhost" >> /etc/apache2/apache2.conf

COPY supervisord.conf /etc/supervisor/conf.d/nagios.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/usr/local/nagios/etc", "/usr/local/nagios/var"]
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/nagios.conf"]
