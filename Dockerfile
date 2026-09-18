# syntax=docker/dockerfile:1
ARG NAGIOS_VERSION=4.5.14
ARG NAGIOS_PLUGINS_VERSION=2.5
ARG NRPE_VERSION=4.1.3
ARG NSCA_VERSION=2.10.3
ARG NCPA_VERSION=3.5.0
ARG NAGIOSGRAPH_VERSION=1.4.4
ARG NAGIOS_EXPORTER_VERSION=1.2.5
ARG GO_VERSION=1.27.1

########################################
# Stage 1: build Nagios Core + Plugins + addons
########################################
FROM ubuntu:26.04 AS builder
ARG NAGIOS_VERSION
ARG NAGIOS_PLUGINS_VERSION
ARG NRPE_VERSION
ARG NSCA_VERSION
ARG NCPA_VERSION
ARG NAGIOSGRAPH_VERSION
ARG NAGIOS_EXPORTER_VERSION
ARG GO_VERSION
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        wget ca-certificates \
        build-essential autoconf gettext bc unzip \
        apache2 apache2-utils \
        libgd-dev libssl-dev libperl-dev libmcrypt-dev \
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

# --- Build NRPE client plugin (check_nrpe only; the nrpe daemon runs on ---
# --- the monitored hosts, not on this Nagios server image)             ---
WORKDIR /usr/src
RUN wget -qO nrpe.tar.gz \
        "https://github.com/NagiosEnterprises/nrpe/releases/download/nrpe-${NRPE_VERSION}/nrpe-${NRPE_VERSION}.tar.gz" \
    && tar xzf nrpe.tar.gz \
    && rm nrpe.tar.gz

WORKDIR /usr/src/nrpe-${NRPE_VERSION}
RUN ./configure \
        --with-pluginsdir=/usr/local/nagios/libexec \
        --with-nagios-user=nagios \
        --with-nagios-group=nagios \
    && make check_nrpe \
    && make install-plugin

# --- Build NSCA server daemon (send_nsca is not needed here; it runs on ---
# --- the monitored hosts that submit passive check results)            ---
WORKDIR /usr/src
RUN wget -qO nsca.tar.gz \
        "https://github.com/NagiosEnterprises/nsca/releases/download/nsca-${NSCA_VERSION}/nsca-${NSCA_VERSION}.tar.gz" \
    && tar xzf nsca.tar.gz \
    && rm nsca.tar.gz

WORKDIR /usr/src/nsca-${NSCA_VERSION}
RUN ./configure \
        --prefix=/usr/local/nagios \
        --with-nsca-user=nagios \
        --with-nsca-grp=nagios \
        --with-nsca-port=5667 \
    && make nsca \
    && install -d /usr/local/nagios/bin \
    && install -m 755 src/nsca /usr/local/nagios/bin/nsca \
    && install -m 640 sample-config/nsca.cfg /usr/local/nagios/etc/nsca.cfg \
    && install -m 640 sample-config/nsca.cfg /usr/local/nagios/nsca.cfg.dist

# --- Fetch NCPA client plugin (check_ncpa.py only; the NCPA agent runs ---
# --- on the monitored hosts, not on this Nagios server image)          ---
RUN wget -qO /usr/local/nagios/libexec/check_ncpa.py \
        "https://raw.githubusercontent.com/NagiosEnterprises/ncpa/v${NCPA_VERSION}/client/check_ncpa.py" \
    && chmod 755 /usr/local/nagios/libexec/check_ncpa.py

# --- Install nagiosgraph (RRD graphing/trending addon) ---
WORKDIR /usr/src
RUN wget -qO nagiosgraph.tar.gz \
        "https://sourceforge.net/projects/nagiosgraph/files/nagiosgraph/${NAGIOSGRAPH_VERSION}/nagiosgraph-${NAGIOSGRAPH_VERSION}.tar.gz/download" \
    && tar xzf nagiosgraph.tar.gz \
    && rm nagiosgraph.tar.gz

WORKDIR /usr/src/nagiosgraph-${NAGIOSGRAPH_VERSION}
RUN install -d /usr/local/nagios/etc/nagiosgraph /usr/local/nagios/var/rrd \
    && install -m 644 -t /usr/local/nagios/etc/nagiosgraph etc/* \
    && install -m 644 -t /usr/local/nagios/share share/nagiosgraph.css share/nagiosgraph.js \
    && sed -i "s#use lib '/opt/nagiosgraph/etc';#use lib '/usr/local/nagios/etc/nagiosgraph';#" \
        lib/insert.pl cgi/*.cgi \
    && install -m 755 lib/insert.pl /usr/local/nagios/libexec/insert.pl \
    && install -m 755 -t /usr/local/nagios/sbin cgi/*.cgi \
    && sed -i \
        -e "s#^logfile[[:space:]]*=.*#logfile = /usr/local/nagios/var/nagiosgraph.log#" \
        -e "s#^cgilogfile[[:space:]]*=.*#cgilogfile = /usr/local/nagios/var/nagiosgraph-cgi.log#" \
        -e "s#^perflog[[:space:]]*=.*#perflog = /usr/local/nagios/var/perfdata.log#" \
        -e "s#^rrddir[[:space:]]*=.*#rrddir = /usr/local/nagios/var/rrd#" \
        -e "s#^mapfile[[:space:]]*=.*#mapfile = /usr/local/nagios/etc/nagiosgraph/map#" \
        -e "s#^nagiosgraphcgiurl[[:space:]]*=.*#nagiosgraphcgiurl = /nagios/cgi-bin#" \
        -e "s#^javascript[[:space:]]*=.*#javascript = /nagios/nagiosgraph.js#" \
        -e "s#^stylesheet[[:space:]]*=.*#stylesheet = /nagios/nagiosgraph.css#" \
        /usr/local/nagios/etc/nagiosgraph/nagiosgraph.conf

# Nagios command definition for nagiosgraph, kept outside the /usr/local/nagios/etc
# volume so the entrypoint can seed it into objects/ on first boot or upgrade.
# Named process-service-perfdata-file (not process-service-perfdata) because
# commands.cfg already defines a command called process-service-perfdata.
RUN printf 'define command {\n    command_name  process-service-perfdata-file\n    command_line  /usr/local/nagios/libexec/insert.pl\n}\n' \
        > /usr/local/nagios/nagiosgraph-command.cfg.dist

# --- Build Prometheus exporter for Nagios from source. Built here (rather ---
# --- than using upstream's prebuilt release binary) so it links against a ---
# --- current Go toolchain/stdlib instead of whatever old Go the upstream  ---
# --- maintainer happened to have locally when they cut that release.     ---
WORKDIR /usr/src
RUN wget -qO go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && tar -C /usr/local -xzf go.tar.gz \
    && rm go.tar.gz

RUN wget -qO nagios_exporter.tar.gz \
        "https://github.com/linode-obs/nagios_exporter/archive/refs/tags/v${NAGIOS_EXPORTER_VERSION}.tar.gz" \
    && tar xzf nagios_exporter.tar.gz \
    && rm nagios_exporter.tar.gz

WORKDIR /usr/src/nagios_exporter-${NAGIOS_EXPORTER_VERSION}
# go.mod pins golang.org/x/net, logrus and protobuf to 2022/2023 releases with
# known CVEs; bump them to current patched versions before building (all are
# v0/v1 modules under Go's compatibility promise, so this is a safe upgrade).
RUN PATH="/usr/local/go/bin:${PATH}" go get -u \
        golang.org/x/net \
        github.com/sirupsen/logrus \
        google.golang.org/protobuf \
    && PATH="/usr/local/go/bin:${PATH}" go mod tidy
RUN PATH="/usr/local/go/bin:${PATH}" GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
        go build -trimpath -ldflags="-s -w -X main.Version=${NAGIOS_EXPORTER_VERSION}" \
        -o /usr/local/nagios/bin/nagios_exporter nagios_exporter.go

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
        libmcrypt4 python3 \
        librrds-perl libgd-gd2-perl libcgi-pm-perl rrdtool \
        supervisor \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/bin/pebble

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
EXPOSE 80 5667 9927

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/nagios.conf"]
