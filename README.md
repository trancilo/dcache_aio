# dCache AIO (dCache all-in-one)

A script that sets up a nice simple dCache all-in-one server.
It creates a self-signed host certificate, but does not use that
(it's only needed to start the service).

Features:
- Auto-detects Linux distribution.
- Installs PostgreSQL and dCache.
- Configures PostgreSQL for dCache.
- Sets up firewall rules.
- Generates a self-signed certificate.
- Supports interactive mode for input if parameters aren't provided.

You'll need to specify two values or you will be prompted to give them.

- the data directory (e.g. /home/datadir
- the password for the test user

Tested on AlmaLinux 9.2
minimal 2 cpu and 2GB memory

DON'T RUN THIS ON A PRODUCTION SERVER!
Use on a test system only, at your own risk!
