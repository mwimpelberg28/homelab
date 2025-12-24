# Raspberry Pi 4 Services

Docker Compose stacks for home services running on a Raspberry Pi 4.

## Stacks
- **Bind9 DNS:** See [bind9/docker-compose.yml](bind9/docker-compose.yml) and configs in [bind9/config/](bind9/config/).
- **Nginx Reverse Proxy:** See [nginxrp/docker-compose.yml](nginxrp/docker-compose.yml) with certs under [nginxrp/letsencrypt/](nginxrp/letsencrypt/).

## Requirements
- Docker and Docker Compose installed on the Pi.
- Correct network connectivity and volumes/paths.

## Usage

Start DNS:
```bash
cd bind9
docker-compose up -d
```

Start reverse proxy:
```bash
cd nginxrp
docker-compose up -d
```

Update zone files in [bind9/config/](bind9/config/) and configure TLS for nginx appropriately.