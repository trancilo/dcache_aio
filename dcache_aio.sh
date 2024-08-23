#!/bin/bash

# dCache AIO (dCache all-in-one)
#
# A script that sets up a nice simple dCache all-in-one server.
# It creates a self-signed host certificate, but does not use that
# (it's only needed to start the service).

# You'll need to specify two values or you will be prompted to give them.

# - the data directory (e.g. /home/datadir
# - the password for the test user

# Tested on AlmaLinux 9.2
# minimal 2 cpu and 2GB memory

# Use on a test system only, at your own risk!
# DON'T RUN THIS ON A PRODUCTION SERVER!

# Default values for variables
DATADIR=""
PASSWD=""

# Help function to explain usage
function show_help {
    echo "Usage: $0 --datadir=<directory> --passwd=<password>"
    echo "  --datadir=DIR   Specify the data directory."
    echo "  --passwd=PASS   Specify the password."
    echo
    echo "Both --datadir and --passwd are required."
    echo "If not provided, you will be prompted to enter them."
    echo
    echo "Information about dCache itself can be found at: https://www.dcache.org"
}

# Parse command line arguments
for arg in "$@"
do
    case $arg in
        --datadir=*)
        DATADIR="${arg#*=}"
        shift
        ;;
        --passwd=*)
        PASSWD="${arg#*=}"
        shift
        ;;
        --help|-h)
        show_help
        exit 0
        ;;
        *)
        echo "Invalid option: $arg"
        show_help
        exit 1
        ;;
    esac
done

# If no arguments were provided or if DATADIR or PASSWD are still empty, display help and prompt
if [ -z "$DATADIR" ] || [ -z "$PASSWD" ]; then
    show_help
    echo
    read -p "No or incomplete arguments provided. Do you want to continue and provide the values interactively? (y/n) " answer
    case $answer in
        [Yy]* )
            echo "Continuing with interactive input..."
            ;;
        * )
            echo "Exiting."
            exit 0
            ;;
    esac
fi

# Prompt for DATADIR if not provided
while [ -z "$DATADIR" ]; do
    read -p "Please enter the DATADIR: " DATADIR
done

# Prompt for PASSWD if not provided
while [ -z "$PASSWD" ]; do
    read -sp "Please enter the PASSWD: " PASSWD
    echo
done

# Display the values
echo "DATADIR is set to: $DATADIR"
echo "PASSWD is set to: $PASSWD"

# Set locales for postgres dbinit
dnf install -y glibc-locale-source glibc-langpack-en
LANG_LOCALE="C.UTF-8"
LC_ALL_LOCALE="C.UTF-8"
echo "Set correct locales for postgres dbinit"

if ! grep -q "^LANG=$LANG_LOCALE" /etc/locale.conf; then
    echo "LANG is already set to $LANG_LOCALE"
fi

if ! grep -q "^LC_ALL=$LC_ALL_LOCALE" /etc/locale.conf; then
    echo "LC_ALL is already set to $LC_ALL_LOCALE"
fi

# Apply the changes
source /etc/locale.conf

# Check if DATADIR is provided
if [ -z "$DATADIR" ]; then
    read -p "Please enter the DATADIR: " DATADIR
fi

# Check if PASSWD is provided
if [ -z "$PASSWD" ]; then
    read -sp "Please enter the PASSWD: " PASSWD
    echo
fi

# Display the values
echo "DATADIR is set to: $DATADIR"
echo "PASSWD is set to: $PASSWD"


if [ -x ${DATADIR} ]; then
    rm -rf ${DATADIR}
fi

# Check if firewalld is running
if systemctl is-active --quiet firewalld; then
    echo "Firewalld is running, applying firewall rules..."

    # Open port for Zookeeper
    firewall-cmd --permanent --zone=public --add-port=2181/tcp

    # Open port for Admin service
    firewall-cmd --permanent --zone=public --add-port=22224/tcp

    # Open port for WebDAV-alma service
    firewall-cmd --permanent --zone=public --add-port=2880/tcp

    # Open ports for Pool1 service
    firewall-cmd --permanent --zone=public --add-port=20000-25000/tcp
    firewall-cmd --permanent --zone=public --add-port=33115-33145/tcp

    # Reload firewalld to apply the changes
    firewall-cmd --reload
    echo "Firewall rules applied successfully."

else
    echo "Firewalld is not running, skipping firewall configuration."
fi


# URL for the specific page where to find the latest dCache
URL="https://www.dcache.org/old/downloads/1.9/index.shtml"

echo "Fetching the downloads page with lynx..."
page_content=$(lynx -dump $URL)

# Extract the latest RPM link
dcache_rpm=$(echo "$page_content" | grep -oP 'https://.*?\.rpm' | sort --version-sort | tail -1)
if [ -z "$dcache_rpm" ]; then
    echo "No RPM found on the page. Please check the URL or page content."
    exit 1
fi
dcache_basename=$(basename ${dcache_rpm})
echo "Latest dCache version URL: $dcache_rpm"
echo "Latest dCache version file: $dcache_basename"

# Check if the file already exists
if [ -f "$dcache_basename" ]; then
    echo "The file $dcache_basename already exists. Skipping download."
else
    echo "Downloading $dcache_basename..."
    curl -s -w "%{http_code}\n" -L $dcache_rpm -O

    if [ $? -eq 0 ]; then
        echo "Download completed successfully."
    else
        echo "Failed to download the file."
        exit 1
    fi
fi

# Extract the required JVM version
required_jvm_version=$(echo "$page_content" | grep -oP 'dCache v[0-9]+\.[0-9]+ requires a JVM supporting Java [0-9]+' | grep -oP '[0-9]+$' | head -1)

# Determine the corresponding OpenJDK package
if [ -z "$required_jvm_version" ]; then
    echo "No specific JVM version required. Installing the latest version of OpenJDK."
    sudo yum install -y java-latest-openjdk-devel
else
    echo "Required JVM version: Java $required_jvm_version"

    # Check if the required JVM version is installed
    if java -version 2>&1 | grep -q "openjdk version \"$required_jvm_version\""; then
        echo "Java $required_jvm_version is already installed."
    else
        echo "Java $required_jvm_version is not installed. Installing it now..."
        sudo yum install -y java-$required_jvm_version-openjdk-devel
    fi
fi

echo "JVM setup is complete."





# Install httpd-tools
dnf install httpd-tools -y

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
#su - postgres -c "createuser --no-superuser --no-createrole --createdb --no-password dcache"
#su - postgres -c "createdb chimera"
#su - postgres -c "psql -c \"ALTER USER dcache WITH SUPERUSER;\""


# Function to check if a PostgreSQL user exists
function user_exists {
    su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$1'\"" | grep -q 1
}

# Function to check if a PostgreSQL database exists
function db_exists {
    su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$1'\"" | grep -q 1
}

# Variables
PG_USER="dcache"
PG_DB="chimera"

# Check and create PostgreSQL user
if user_exists "$PG_USER"; then
    echo "User '$PG_USER' already exists. Skipping user creation."
else
    echo "Creating PostgreSQL user '$PG_USER'..."
    su - postgres -c "createuser --no-superuser --no-createrole --createdb --no-password $PG_USER"
    echo "User '$PG_USER' created successfully."
fi

# Check and create PostgreSQL database
if db_exists "$PG_DB"; then
    echo "Database '$PG_DB' already exists. Skipping database creation."
else
    echo "Creating PostgreSQL database '$PG_DB'..."
    su - postgres -c "createdb $PG_DB"
    echo "Database '$PG_DB' created successfully."
fi

# Alter user to have superuser privileges
echo "Altering user '$PG_USER' to have SUPERUSER privileges..."
su - postgres -c "psql -c \"ALTER USER $PG_USER WITH SUPERUSER;\""
echo "User '$PG_USER' altered successfully."

echo "PostgreSQL configuration completed."

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
systemctl stop dcache.target
systemctl start dcache.target

# Give dCache some time to startup
echo -n "Waiting for dCache to initialize "

# Show the growing line of asterisks for 5 seconds
for ((j=1; j<=10; j++)); do
    echo -ne "\rWaiting for dCache to initialize $(printf '%*s' "$j" | tr ' ' '*')"
    sleep 0.5  # Sleep 0.5 seconds per step, so 10 steps = 5 seconds total
done

# Move to a new line before checking the service
echo -ne "\rChecking if dcache service is started "

sleep 1

# Loop until the dcache service is active
while ! systemctl is-active --quiet dcache.target; do
    for ((j=1; j<=10; j++)); do
        echo -ne "\rChecking if dcache service is started $(printf '%*s' "$j" | tr ' ' '*')"
        sleep 0.1
    done
done

sleep 1

echo -ne "\rDone!                                     \n"

echo " "
echo "You can test uploading the README.md file with webdav now:"
echo "curl -v -u tester:$PASSWD -L -T README.md http://localhost:2880/home/tester/README.md"
echo "Admin console: ssh -p 22224 admin@localhost \(with your provided password $PASSWD\)"
