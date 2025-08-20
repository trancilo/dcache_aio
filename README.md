# dCache AIO (dCache all-in-one)

A script that sets up a nice simple dCache all-in-one server.
It can be used to test functionality and try out specific versions of dCache.

Setting up a dCache instance using the [dcache book](https://www.dcache.org/manuals/Book-10.2/) 
can be time consuming. This script will make it easy to get started and can be used as guide to see which steps are needed to get to a running instance and how to configure a [hsm](https://www.dcache.org/manuals/Book-10.2/cookbook-writing-hsm-plugins.shtml) tape-backend.<br>
❢ Currently this script is not yet fully idempotent. Which means running it multiple times might cause things to break. Generally this should be fine but don't count on it.


Features:
- Adds a fake tape backend
  - using a simple (hsm) ruby script to copy files to a secondary directory
  - add a tape pool which is configured to use this script hsm script
- Installs PostgreSQL and dCache.
- Configures PostgreSQL for dCache.
- Sets up firewall rules.
- Generates a self-signed certificate.
- Sets up a webdav door with https
- Sets up a frontend/api door with https
- Supports interactive mode for input if parameters aren't provided.

You'll need to specify three values or you will be prompted to give them.

- the data directory: dCache will store its data here.
- the password for the test user. Username is already set to "tester".
- location for the fake tape backend: Files which are set to be transfered to tape by the hsm script will be stored here.

Tested on AlmaLinux 9.6<br>
minimal 2 cpu and 2GB memory

❢ DON'T RUN THIS ON A PRODUCTION SERVER!<br>
❢ Use on a test system only, at your own risk!
