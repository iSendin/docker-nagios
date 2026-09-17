# Nagios Core Docker Image

Imagen Docker de [Nagios Core](https://www.nagios.org/projects/nagios-core/) 4.5.14 con Nagios Plugins 2.5, compilados desde el código fuente oficial sobre Ubuntu 26.04 LTS, con Apache + PHP para la interfaz web.

Incluye además los siguientes complementos:

| Complemento | Versión | Qué incluye esta imagen |
|---|---|---|
| [Nagios Plugins](https://github.com/nagios-plugins/nagios-plugins) | 2.5 | Plugins estándar de chequeo (`check_ping`, `check_http`, `check_disk`, etc.) |
| [NRPE](https://github.com/NagiosEnterprises/nrpe) | 4.1.3 | Solo el plugin cliente `check_nrpe` (para consultar el daemon `nrpe` que corre en los hosts remotos monitorizados) |
| [NCPA](https://github.com/NagiosEnterprises/ncpa) | 3.5.0 | Solo el plugin cliente `check_ncpa.py` (para consultar el agente NCPA que corre en los hosts remotos monitorizados) |
| [NSCA](https://github.com/NagiosEnterprises/nsca) | 2.10.3 | El daemon servidor `nsca` completo, en ejecución (recibe chequeos pasivos enviados con `send_nsca` desde los hosts remotos) |
| [nagiosgraph](https://exchange.nagios.org/directory/addons/graphing-and-trending/nagiosgraph/details) | 1.4.4 | Graficado y tendencias en RRD a partir de los datos de rendimiento de los plugins |
| [nagios_exporter](https://github.com/linode-obs/nagios_exporter) | 1.2.5 | Exportador Prometheus con métricas del propio servidor Nagios (nº de hosts/servicios, estados, flapping, downtime, etc.) |

**Importante — quién corre dónde:**
- **NRPE y NCPA** son agentes que se instalan en las máquinas que quieres monitorizar, no en este servidor. Aquí solo se incluyen los plugins cliente que los consultan (`check_nrpe`, `check_ncpa.py`).
- **NSCA** es al revés: el daemon `nsca` corre en este servidor, y son los hosts remotos los que necesitan `send_nsca` para enviarle resultados de chequeos pasivos.
- **nagiosgraph** y **nagios_exporter** corren enteramente en este servidor; no requieren nada instalado en los hosts remotos.

## Uso rápido

```bash
docker run -d \
  -p 8080:80 \
  -p 5667:5667 \
  -p 9927:9927 \
  -e NAGIOSADMIN_PASSWORD=tu_password \
  -e NSCA_PASSWORD=tu_password_nsca \
  --name nagios \
  isendin/nagios-core:latest
```

Interfaz web: `http://localhost:8080/nagios` (usuario `nagiosadmin`, la contraseña que hayas puesto en `NAGIOSADMIN_PASSWORD`; por defecto `admin`).

## Variables de entorno

| Variable | Descripción | Por defecto |
|---|---|---|
| `NAGIOSADMIN_USER` | Usuario admin de la interfaz web | `nagiosadmin` |
| `NAGIOSADMIN_PASSWORD` | Contraseña del usuario admin | `admin` |
| `NSCA_PASSWORD` | Contraseña/passphrase para cifrar los paquetes NSCA. Debe coincidir con la configurada en `send_nsca.cfg` de los hosts remotos | `nsca` |
| `NSCA_ENCRYPTION_METHOD` | Método de cifrado NSCA (`decryption_method` en `nsca.cfg`; ver [tabla de valores](https://github.com/NagiosEnterprises/nsca/blob/nsca-2.10.3/sample-config/nsca.cfg.in)) | `14` (RIJNDAEL-128/AES) |

## Puertos

| Puerto | Servicio |
|---|---|
| `80` | Interfaz web (Apache) |
| `5667` | Daemon NSCA (recepción de chequeos pasivos) |
| `9927` | Métricas Prometheus de `nagios_exporter` (`/metrics`) |

## Servicios en ejecución (supervisord)

| Proceso | Usuario | Descripción |
|---|---|---|
| `apache2` | root (workers como `www-data`) | Interfaz web y CGIs |
| `nagios` | `nagios` | Motor de monitorización |
| `nsca` | `nagios` | Recepción de chequeos pasivos (puerto 5667) |
| `nagios_exporter` | `nagios` | Métricas Prometheus (puerto 9927), lee `nagiostats` directamente, sin API HTTP |

## nagiosgraph — graficado con RRDtool

Al arrancar, el contenedor habilita automáticamente el procesado de datos de rendimiento en `nagios.cfg` (`process_performance_data`, `service_perfdata_file*`) y registra el comando `process-service-perfdata-file` (nombre elegido para no chocar con el `process-service-perfdata` que Nagios Core ya trae definido por defecto en `commands.cfg`), que invoca `insert.pl` para volcar los datos a RRD.

Rutas relevantes:

| Ruta | Contenido |
|---|---|
| `/usr/local/nagios/etc/nagiosgraph/` | Configuración de nagiosgraph (`nagiosgraph.conf`, `map`, `*db.conf`) — personalizable, vive en el volumen `etc` |
| `/usr/local/nagios/var/rrd/` | Bases de datos RRD generadas | 
| `/usr/local/nagios/var/perfdata.log` | Cola de datos de rendimiento pendientes de insertar |

Para ver las gráficas, accede directamente a los CGI (no están enlazados en el menú lateral de Nagios por defecto):

- `http://localhost:8080/nagios/cgi-bin/show.cgi` — listado general
- `http://localhost:8080/nagios/cgi-bin/showhost.cgi?host=<host>` — gráficas por host
- `http://localhost:8080/nagios/cgi-bin/showservice.cgi?service=<servicio>` — gráficas por servicio

Si quieres enlaces en el menú lateral o el icono de acción de Nagios sustituido por el de nagiosgraph, son personalizaciones manuales sobre `/usr/local/nagios/share/side.php` y `/usr/local/nagios/share/images/action.gif` (fuera del alcance de esta imagen, ya que no persisten en volumen y se perderían en cada rebuild).

## nagios_exporter — métricas Prometheus

Expone en `http://localhost:9927/metrics` métricas sobre el propio Nagios (hosts/servicios activos, pasivos, en downtime, flapping, etc.), leyendo el binario `nagiostats` incluido en la imagen. No expone los resultados de cada chequeo individual como métricas — para eso hace falta un exporter distinto por tipo de recurso monitorizado.

Ejemplo de scrape config de Prometheus:

```yaml
scrape_configs:
  - job_name: nagios
    static_configs:
      - targets: ["nagios-core:9927"]
```

## Volúmenes

| Ruta | Contenido |
|---|---|
| `/usr/local/nagios/etc` | Configuración (incluye `nsca.cfg`, `nagiosgraph/`) |
| `/usr/local/nagios/var` | Estado, logs y RRD (`var/rrd`) |

## Con docker-compose

```yaml
services:
  nagios:
    image: isendin/nagios-core:latest
    ports:
      - "8080:80"
      - "5667:5667"
      - "9927:9927"
    environment:
      NAGIOSADMIN_PASSWORD: "admin"
      NSCA_PASSWORD: "nsca"
    volumes:
      - nagios-etc:/usr/local/nagios/etc
      - nagios-var:/usr/local/nagios/var

volumes:
  nagios-etc:
  nagios-var:
```

## Build

Imagen construida y publicada automáticamente mediante GitHub Actions a partir de este repositorio.

Las versiones de cada componente se controlan mediante `ARG` en el `Dockerfile` (`NAGIOS_VERSION`, `NAGIOS_PLUGINS_VERSION`, `NRPE_VERSION`, `NSCA_VERSION`, `NCPA_VERSION`, `NAGIOSGRAPH_VERSION`, `NAGIOS_EXPORTER_VERSION`), por lo que se pueden sobreescribir en el build sin tocar el resto del código:

```bash
docker build --build-arg NRPE_VERSION=4.1.3 -t nagios-core .
```
