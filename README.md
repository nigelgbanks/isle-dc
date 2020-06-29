# ISLE: Islandora Enterprise 8 Prototype

[![LICENSE](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](./LICENSE)

## Introduction

Docker-Compose project facilitating creation and management of Islandora 8
Infrastructure under Docker.

## Developer Notes

This is a prototype of the `docker-compose` file, Docker service and image
configuration structure for the ISLE Phase III - ISLE / Islandora 8 Prototype
(isle-dc) project.

## Requirements

* Desktop / laptop / VM
* Docker-CE 19.x+
  * If using Docker Desktop for Windows, any stable release *after* 2.2.0.4, or use a 2.2.0.4 with a [patch](https://download-stage.docker.com/win/stable/43542/Docker%20Desktop%20Installer.exe) due to a [bug](https://github.com/docker/for-win/issues/6016)
* Docker-compose version 1.25.x+
* Git 2.0+

## Installation

* For stable working use the `master` branch
* For bleeding edge, potentially not working, use the `development` branch

* use `docs/recipes/*` for current installation steps, depending on if you want to run a demo or a local dev environment.

## Configuration

* The `config` directory currently holds all settings and configurations for the Dockerized Islandora 8 stack services and is the `./config` path found within the `docker-compose.yml`.

## Documentation

* All documentation for this project can be found within the `docs` directory.

To run the Docker images with Docker Compose requires:

### Watchtower

The [watchtower](https://hub.docker.com/r/v2tec/watchtower/) container monitors
the running Docker containers and watches for changes to the images that those
containers were originally started from. If watchtower detects that an image has
changed, it will automatically restart the container using the new image. This
allows for automatic deployment, and overall faster development time.

Note however Watchtower will not restart stopped container or containers that
exited due to error. To ensure a container is always running, unless explicitly
stopped, add ``restart: unless-stopped`` property to the container in the
[docker-compose.yml] file. For example:

```yaml
database:
    image: islandora/mariadb:latest
    restart: unless-stopped
```

### Traefik

The [traefik](https://containo.us/traefik/) container acts as a reverse proxy,
and exposes some containers through port ``80`` on the localhost via the
[loopback](https://www.tldp.org/LDP/nag/node66.html). This allows access to the
following urls.

- <http://activemq.isle-dc.localhost/admin>
- <http://blazegraph.isle-dc.localhost/bigdata>
- <http://islandora.isle-dc.localhost>
- <http://fcrepo.isle-dc.localhost/fcrepo/reset>
- <http://matomo.isle-dc.localhost>

Note if you cannot map ``traefik`` to the hosts port 80, you will need to
manually modify your ``/etc/hosts`` file and add entries for each of the urls
above like so, assuming the IP of ``traefik`` container is ``x.x.x.x`` on its
virtual network, and you can access that address from your machine.

```properties
x.x.x.x     activemq.isle-dc.localhost
x.x.x.x     blazegraph.isle-dc.localhost
x.x.x.x     islandora.isle-dc.localhost
x.x.x.x     fcrepo.isle-dc.localhost
x.x.x.x     matomo.isle-dc.localhost
```

Since Drupal passes its ``Base URL`` along to other services in AS2 as a means
of allowing them to find their way back. As well as having services like Fedora
exposed at the same URL they are accessed by the micro-services to end users. We
need to allow containers within the network to be accessible via the same URL,
though not by routing through ``traefik`` since it is and edge router.

So alias like the following are defined:

```yaml
drupal:
    image: islandora/demo:latest
    # ...
    networks:
      default:
        aliases:
          - islandora.isle-dc.localhost
```

These are set on the ``default`` network as that is the internal network (no
access to the outside) on which all containers reside.

## Running

To run the containers you must first generate a `docker-compose.yml` file. It is
the only orchestration mechanism provided to launch all the containers, and have
them work as a whole. To generate the `docker-compose.yml` from your settings in `.env`

To start the containers use the following command:

```bash
docker-compose up -d
```

With [Docker Compose] there are many features such as displaying logs among
other things for which you can find detailed descriptions in the
[Docker Composer CLI Documentation](https://docs.docker.com/compose/reference/overview/)

For more information on the structure and design of the example
[docker-compose.yml] file see the [Docker Compose](#Docker-Compose) section of
this document.

## Scripts

Some helper scripts are provided to make development and testing more pleasurable.

- [./commands/drush.sh](./commands/drush.sh) - Wrapper around [drush] in the ``drupal service`` container.
- [./commands/etcdctrl.sh](./commands/etcdctrl.sh) - Wrapper around [etcdctrl] in the ``etcd service`` container.
- [./commands/mysql.sh](./commands/mysql.sh) - Wrapper around [mysql] client in the ``database service`` container.
- [./commands/open-in-browser.sh](./commands/shell.sh) - Attempts to open the given service in the users browser.
- [./commands/shell.sh](./commands/shell.sh) - Open ``ash`` shell in the given service container.

All of the above commands include a usage statement, which can be accessed with ``-h`` flag like so:

```bash
$ ./commands/shell.sh
    usage: shell.sh SERVICE

    Opens an ash shell in the given SERVICE's container.

    OPTIONS:
       -h --help          Show this help.
       -x --debug         Debug this script.

    Examples:
       shell.sh database
```

## Connect

* Coming soon

## Troubleshooting/Issues

Post your questions here and subscribe for updates, meeting announcements, and technical support

* [Islandora ISLE Interest Group](https://github.com/islandora-interest-groups/Islandora-ISLE-Interest-Group) - Meetings open to everybody! 
  * [Schedule](https://github.com/islandora-interest-groups/Islandora-ISLE-Interest-Group/#how-to-join) is alternating Wednesdays, 3:00pm EDT
* [Islandora ISLE Google group](https://groups.google.com/forum/#!forum/islandora-isle)
* [Islandora ISLE Slack channel](https://islandora.slack.com) `#isle`
* [Islandora Group](https://groups.google.com/forum/?hl=en&fromgroups#!forum/islandora)
* [Islandora Dev Group](https://groups.google.com/forum/?hl=en&fromgroups#!forum/islandora-dev)

## FAQ

* Coming soon

## Development

If you would like to contribute to this project, please check out [CONTRIBUTING.md](CONTRIBUTING.md). In addition, we have helpful [Documentation for Developers](https://github.com/Islandora/islandora/wiki#wiki-documentation-for-developers) info, as well as our [Developers](http://islandora.ca/developers) section on the [Islandora.ca](http://islandora.ca) site.

## Maintainers/Sponsors

### Architecture Team

* [Jeffery Antoniuk](https://github.com/jefferya), Canadian Writing Research Collaboratory
* [Nia Kathoni](https://github.com/nikathone), Canadian Writing Research Collaboratory
* [Aaron Birkland](https://github.com/birkland), Johns Hopkins University
* [Jonathan Green](https://github.com/jonathangreen), LYRASIS
* [Danny Lamb](https://github.com/dannylamb), Islandora Foundation
* [Gavin Morris](https://github.com/g7morris) (Project Tech Lead), Born-Digital
* [Mark Sandford](https://github.com/marksandford) (Documentation Lead), Colgate University
* [Daniel Bernstein](https://github.com/dbernstein), LYRASIS

## Sponsors

This project has been sponsored by:

Grinnell College
Tri-College (Bryn Mawr College, Haverford College, Swarthmore College)
Wesleyan University
Williams College
Colgate University
Hamilton College
Amherst College
Mount Holyoke College
Franklin and Marshall College
Whitman College
Smith College
Arizona State University
Canadian Writing Research Collaboratory (CWRC)
Johns Hopkins University
Tulane University
LYRASIS
Born-Digital

## License

[MIT](https://opensource.org/licenses/MIT)