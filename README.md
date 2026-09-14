# Nagios Core Docker Image

Imagen Docker de [Nagios Core](https://www.nagios.org/projects/nagios-core/) 4.5.14 con Nagios Plugins 2.5, compilados desde el código fuente oficial sobre Ubuntu 26.04 LTS, con Apache + PHP para la interfaz web.

## Uso rápido

```bash
docker run -d \
  -p 8080:80 \
  -e NAGIOSADMIN_PASSWORD=tu_password \
  --name nagios \
  isendin/nagios-core:latest
```

Interfaz web: `http://localhost:8080/nagios` (usuario `nagiosadmin`, la contraseña que hayas puesto en `NAGIOSADMIN_PASSWORD`; por defecto `admin`).

## Variables de entorno

| Variable | Descripción | Por defecto |
|---|---|---|
| `NAGIOSADMIN_USER` | Usuario admin de la interfaz web | `nagiosadmin` |
| `NAGIOSADMIN_PASSWORD` | Contraseña del usuario admin | `admin` |

## Volúmenes

| Ruta | Contenido |
|---|---|
| `/usr/local/nagios/etc` | Configuración |
| `/usr/local/nagios/var` | Estado y logs |

## Con docker-compose

```yaml
services:
  nagios:
    image: isendin/nagios-core:latest
    ports:
      - "8080:80"
    environment:
      NAGIOSADMIN_PASSWORD: "admin"
    volumes:
      - nagios-etc:/usr/local/nagios/etc
      - nagios-var:/usr/local/nagios/var

volumes:
  nagios-etc:
  nagios-var:
```

## Build

Imagen construida y publicada automáticamente mediante GitHub Actions a partir de este repositorio.
