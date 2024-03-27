#!/bin/bash

# dCache AIO
# tested on Alma9

# You need to supply these values
DATADIR=
PASSWD=

if [ -x ${DATADIR} ]; then
    rm -rf ${DATADIR}
fi

# Open port 2880 for webdav in firwalld
firewall-cmd --permanent --zone=public --add-port=2880/tcp
systemctl restart firewalld


dnf install lynx wget -y

# Get latest dCache version
# Get the full url and the base name
URL="https://www.dcache.org/old/downloads/1.9/index.shtml"
dcache_basename=`lynx -dump -nonumbers ${URL} | grep dcache | grep https | grep rpm | sed 's/.*dcache/dcache/' | sort --version-sort | tail -1`
dcache=`lynx -dump -nonumbers ${URL} | grep dcache | grep https | grep rpm | sort --version-sort | tail -1`

if [ ! -f ${dcache_basename} ]; then
    wget ${dcache}
fi

# Install openjdk
dnf install java-11-openjdk-headless httpd-tools -y

# Install postgresql
not_installed=`rpm -qa | grep postgres >/dev/null 2>&1; echo $?`
if [ "x${not_installed}" == "x1" ]; then
    sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    sudo dnf -qy module disable postgresql
    sudo dnf install -y postgresql16-server
fi
sudo /usr/pgsql-16/bin/postgresql-16-setup initdb
sudo systemctl enable postgresql-16
sudo systemctl start postgresql-16

# Modify pg_hba.conf
cat /var/lib/pgsql/16/data/pg_hba.conf | grep -E 'all\s+all' | sed -i 's/scram-sha-256/trust/' /var/lib/pgsql/16/data/pg_hba.conf

sudo systemctl restart postgresql-16

# Install the dcache rpm
dnf install ./${dcache_basename} -y

# Postgres configuration
su - postgres -c "createuser --no-superuser --no-createrole --createdb --no-password dcache"
su - postgres -c "createdb chimera"
su - postgres -c "psql -c \"ALTER USER dcache WITH SUPERUSER;\""

# dCache configuration
if [ -f /etc/dcache/dcache.conf ]; then
    not_edited=`cat /etc/dcache/dcache.conf | grep 'dcache.layout' >/dev/null 2>&1 ; echo $?`
    if [ "x$not_edited" == "x1" ]; then
        echo "dcache.layout=mylayout" >> /etc/dcache/dcache.conf
    fi
fi

cat <<'EOF' >/etc/dcache/layouts/mylayout.conf
dcache.enable.space-reservation = false

[dCacheDomain]
 dcache.broker.scheme = none
[dCacheDomain/zookeeper]
[dCacheDomain/admin]
[dCacheDomain/pnfsmanager]
 pnfsmanager.default-retention-policy = REPLICA
 pnfsmanager.default-access-latency = ONLINE

[dCacheDomain/cleaner-disk]
[dCacheDomain/poolmanager]
[dCacheDomain/billing]
[dCacheDomain/gplazma]
[dCacheDomain/webdav]
 webdav.authn.basic = true
EOF

cat <<'EOF' >/etc/dcache/gplazma.conf
auth     sufficient  htpasswd
map      sufficient  multimap
account  requisite   banfile
session  requisite   authzdb
EOF

touch /etc/dcache/htpasswd
htpasswd -bm /etc/dcache/htpasswd tester ${PASSWD}
htpasswd -bm /etc/dcache/htpasswd admin ${PASSWD}

cat <<'EOF' > /etc/dcache/multi-mapfile
username:tester uid:1000 gid:1000,true
username:admin uid:0 gid:0,true
EOF

touch /etc/dcache/ban.conf

# This is a bit peculiar. In order to start pools you need x509 certificates.
# Eventhough you don't use them.
mkdir -p /etc/grid-security
touch /etc/grid-security/hostkey.pem
touch /etc/grid-security/hostcert.pem
mkdir -p /etc/grid-security/certificates

# Generate phony key and self-signed certificate to make pools start
openssl genrsa 2048 > /etc/grid-security/hostkey.pem
openssl req -x509 -days 1000 -new -subj "/C=NL/ST=Amsterdam/O=SURF/OU=ODS/CN=localhost" -key /etc/grid-security/hostkey.pem -out /etc/grid-security/hostcert.pem

cat <<'EOF' > /etc/grid-security/storage-authzdb
version 2.1

authorize tester read-write 1000 1000 /home/tester /
authorize admin read-write 0 0 / /
EOF

# Create pool
mkdir -p ${DATADIR}
dcache pool create ${DATADIR}/pool-1 pool1 dCacheDomain

# Update dcache databases
dcache database update

# Create directories
chimera mkdir /home
chimera mkdir /home/tester
chimera chown 1000:1000 /home/tester

# Start dcache
systemctl daemon-reload
systemctl start dcache.target
