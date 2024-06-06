# dcache_aio

A script that sets up a nice simple dCache all-in-one server.
It creates a self-signed host certificate, but does not use that 
(it's only needed to start the service).

You'll need to specify two values:

- the data directory
- the password for the test user

DON'T RUN THIS ON A PRODUCTION SERVER!
Use on a test system only, at your own risk!
