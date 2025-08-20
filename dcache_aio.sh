#!/bin/bash

# dCache AIO (dCache all-in-one)
#
# A script that sets up a nice simple dCache all-in-one server.
# It creates a self-signed host certificate, but does not use that
# (it's only needed to start the service).

# You'll need to specify two values or you will be prompted to give them.

# - the data directory (e.g. /home/datadir
# - the password for the test user

# Tested on AlmaLinux 9.6
# minimal 2 cpu and 2GB memory

# Use on a test system only, at your own risk!
# DON'T RUN THIS ON A PRODUCTION SERVER!


# Help function to explain usage
function show_help {
    echo "This script will install a basic dCache instance on a test server."
    echo "Do not run this on a production system!"
    echo
    echo "Usage: $0 --datadir=<directory> --passwd=<password> --hsmbase=<directory>"
    echo "  --datadir=DIR   Specify the data directory."
    echo "  --hsmbase=DIR   Specify a fake tape backend filesystem (not same as datadir)"
    echo "  --passwd=PASS   Specify the password."
    echo
    echo "Both --datadir and --passwd are required."
    echo "If not provided, you will be prompted to enter them."
    echo
    echo "Information about dCache itself can be found at: https://www.dcache.org"
}

# Wrapper logging function
log() {
    local symbol="❱"
    echo "$symbol $@"
}

# Initializing default values for variables
DATADIR=""
HSMBASE=""
PASSWD=""

# Parse command line arguments
for arg in "$@"
do
    case $arg in
        --datadir=*)
        DATADIR="${arg#*=}"
        shift
        ;;
        --hsmbase=*)
        HSMBASE="${arg#*=}"
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
    read -r -p "No or incomplete arguments provided. Do you want to continue and provide the values interactively? (y/n) " answer
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

# Prompt for DATADIR until it's not empty and exists
while [ -z "$DATADIR" ] || [ ! -d "$DATADIR" ] ; do
  read -r -p "Enter DATADIR (must be an existing directory): " DATADIR
  if [ -z "$DATADIR" ]; then
    echo "DATADIR cannot be empty."
  elif [ ! -d "$DATADIR" ]; then
    echo "Directory '$DATADIR' does not exist."
  fi
done

# Prompt for HSMBASE until it's not empty and exists
while [ -z "$HSMBASE" ] || [ ! -d "$HSMBASE" ] || [ "$HSMBASE" == "$DATADIR" ] ; do
  read -r -p "Enter HSMBASE (must be an existing directory, not the same as DATADIR): " HSMBASE
  if [ -z "$HSMBASE" ]; then
    echo "DATADIR cannot be empty."
  elif [ ! -d "$HSMBASE" ]; then
    echo "Directory '$HSMBASE' does not exist."
  elif [ "$HSMBASE" == "$DATADIR" ]; then
    echo "Directory HSMBASE should not be the same as DATADIR."
  fi
done

# Prompt for PASSWD until it's not empty
while [ -z "$PASSWD" ]; do
  read -rp "Enter PASSWD (cannot be empty): " PASSWD
  echo  # for newline
  if [ -z "$PASSWD" ]; then
    echo "PASSWD cannot be empty."
  fi
done

# Display the values
log "DATADIR is set to: $DATADIR"
log "HSMBASE is set to: $HSMBASE"
log "PASSWD is set to: $PASSWD"


# Set locales for postgres dbinit
dnf install -y glibc-locale-source glibc-langpack-en
LANG_LOCALE="C.UTF-8"
LC_ALL_LOCALE="C.UTF-8"
log "Set correct locales for postgres dbinit"

if ! grep -q "^LANG=$LANG_LOCALE" /etc/locale.conf; then
    echo "LANG is already set to $LANG_LOCALE"
fi

if ! grep -q "^LC_ALL=$LC_ALL_LOCALE" /etc/locale.conf; then
    echo "LC_ALL is already set to $LC_ALL_LOCALE"
fi

# Apply the changes
source /etc/locale.conf

PAGE_URL="https://www.dcache.org/downloads/"
HTML=$(curl -s "$PAGE_URL")

# Extract versions and URLs
mapfile -t VERSIONS < <(echo "$HTML" | ./htmlq -t 'h2#binary-packages + ul li a')
mapfile -t LINKS < <(echo "$HTML" | ./htmlq 'h2#binary-packages + ul li a' --attribute href)

# Display menu
log "Select major and minor verion:"
select VER in "${VERSIONS[@]}"; do
    if [[ -n "$VER" ]]; then
        INDEX=$((REPLY - 1))
        SELECTED_URL="${PAGE_URL}${LINKS[$INDEX]}"
        log "You selected: $VER"
        break
    else
        log "Invalid selection."
    fi
done

export COLUMNS=1

PAGE2_URL=$SELECTED_URL
DCACHE_BASE_URL="https://www.dcache.org"

HTML2=$(curl -s "$PAGE2_URL")

# for now we only support rpm's so a grep takes care of that
mapfile -t PACKAGES < <(echo "$HTML2" | ./htmlq -t 'table.releases td.link a' | grep -v '^[[:space:]]*$' |grep rpm)
mapfile -t PACKAGELINKS < <(echo "$HTML2" | ./htmlq 'table.releases td.link a' --attribute href | grep -v '^[[:space:]]*$' |grep rpm)

# Display menu
log "Select patch version:"
select PACK in "${PACKAGES[@]}"; do
    if [[ -n "$PACK" ]]; then
        INDEX=$((REPLY - 1))
        SELECTED_PACKAGE_URL="${DCACHE_BASE_URL}${PACKAGELINKS[$INDEX]}"
        log "You selected: $PACK"
        break
    else
        log "Invalid selection."
    fi
done
dcache_rpm=$SELECTED_PACKAGE_URL
dcache_basename=$(basename $dcache_rpm)

# Download RPM if the file does not yet exist
if [ -f "$dcache_basename" ]; then
    log "The file $dcache_basename already exists. Skipping download."
else
    log "Downloading $dcache_basename..."
    if curl --fail -s -w "%{http_code}\n" -L "$dcache_rpm" -O  ; then
        log "Download completed successfully."
    else
        log "Failed to download the file."
        exit 1
    fi
fi


# Check if firewalld is running
if systemctl is-active --quiet firewalld; then
    log "Firewalld is running, applying firewall rules..."

    # Open port for Zookeeper
    firewall-cmd --permanent --zone=public --add-port=2181/tcp

    # Open port for Admin service
    firewall-cmd --permanent --zone=public --add-port=22224/tcp

    # Open port for WebDAV doors
    firewall-cmd --permanent --zone=public --add-port=2880-2881/tcp

    # Open door for dCacheView and REST API
    firewall-cmd --permanent --zone=public --add-port=3880/tcp

    # Open ports for Pool1 service
    firewall-cmd --permanent --zone=public --add-port=20000-25000/tcp
    firewall-cmd --permanent --zone=public --add-port=33115-33145/tcp

    # Reload firewalld to apply the changes
    firewall-cmd --reload
    log "Firewall rules applied successfully."

else
    log "Firewalld is not running, skipping firewall configuration."
fi


# install java and ruby
log "install java17 and ruby"
dnf install -y java-17-openjdk-devel.x86_64 ruby


# Install httpd-tools
dnf install httpd-tools -y

# Install postgresql
pg_version=17
if ! rpm -qa | grep --silent postgres ; then
    sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    sudo dnf -qy module disable postgresql
    sudo dnf install -y "postgresql${pg_version}-server"
fi
sudo "/usr/pgsql-${pg_version}/bin/postgresql-${pg_version}-setup" initdb
sudo systemctl enable "postgresql-${pg_version}"
sudo systemctl start  "postgresql-${pg_version}"

# Modify pg_hba.conf
cat /var/lib/pgsql/${pg_version}/data/pg_hba.conf | grep -E 'all\s+all' | sed -i 's/scram-sha-256/trust/' /var/lib/pgsql/${pg_version}/data/pg_hba.conf

sudo systemctl restart "postgresql-${pg_version}"

# Install the dcache rpm
dnf install "./${dcache_basename}" -y

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
PG_DB="chimera pinmanager bulk"

# Check and create PostgreSQL user
if user_exists "$PG_USER"; then
    log "User '$PG_USER' already exists. Skipping user creation."
else
    log "Creating PostgreSQL user '$PG_USER'..."
    su - postgres -c "createuser --no-superuser --no-createrole --createdb --no-password $PG_USER"
    log "User '$PG_USER' created successfully."
fi

# Check and create PostgreSQL database
for database in $PG_DB ; do
  if db_exists "$database"; then
    log "Database '$database' already exists. Skipping database creation."
  else
    log "Creating PostgreSQL database '$database'..."
    su - postgres -c "createdb $database"
    log "Database '$database' created successfully."
  fi
done

# Alter user to have superuser privileges
log "Altering user '$PG_USER' to have SUPERUSER privileges..."
su - postgres -c "psql -c \"ALTER USER $PG_USER WITH SUPERUSER;\""
log "User '$PG_USER' altered successfully."

log "PostgreSQL configuration completed."

# Create sshkey for admin interface
sshkey="/root/.ssh/id_ed25519"
if [ -f "$sshkey" ]; then
    log "ssh private key $sshkey already created"
else
    log "generate sshkey for root"
    ssh-keygen -t ed25519 -N "" -f $sshkey -q
    log "add root ssh publickey: $sshkey to admin interface authorized_keys"
    cat "${sshkey}.pub" |sed 's/root@/admin@/' >> /etc/dcache/admin/authorized_keys2
fi

log "Writing dCache configuration files."
log "  /etc/dcache/dcache.conf"
# dCache configuration
if [ -f /etc/dcache/dcache.conf ]; then
    if ! grep --silent 'dcache.layout' /etc/dcache/dcache.conf ; then
        echo "dcache.layout=mylayout" >> /etc/dcache/dcache.conf
    fi
fi

defaultIP=$(ip -4 addr show $(ip -4 route show default | awk '{print $5}') | grep "inet " | awk '{print $2}' |cut -d "/" -f 1
)
log "Default IP is: $defaultIP"
layoutfile="/etc/dcache/layouts/mylayout.conf"
log "  $layoutfile"
if [ -f "$layoutfile" ]; then
  log "Layoutfile: $layoutfile already exists. Not overwriting"
else
cat <<EOF >$layoutfile
dcache.enable.space-reservation = false
dcache.log.destination=file

[dCacheDomain]
dcache.broker.scheme = core
[dCacheDomain/zookeeper]
[dCacheDomain/admin]
[dCacheDomain/pnfsmanager]
 pnfsmanager.default-retention-policy = REPLICA
 pnfsmanager.default-access-latency = ONLINE

[dCacheDomain/poolmanager]
[dCacheDomain/pinmanager]
[dCacheDomain/billing]
[dCacheDomain/cleaner-disk]
[dCacheDomain/gplazma]
[dCacheDomain/webdav]
 webdav.authn.protocol = https
 webdav.authn.basic = true

[dCacheDomain/frontend]
frontend.static!dcache-view.endpoints.webdav=https://${defaultIP}:2880
[dCacheDomain/bulk]
EOF

fi


log "  /etc/dcache/gplazma.conf"
cat <<'EOF' >/etc/dcache/gplazma.conf
auth     sufficient  htpasswd
map      sufficient  multimap
account  requisite   banfile
session  requisite   authzdb
EOF

log "  /etc/dcache/htpasswd"
touch /etc/dcache/htpasswd
htpasswd -bm /etc/dcache/htpasswd tester "${PASSWD}"
htpasswd -bm /etc/dcache/htpasswd admin  "${PASSWD}"

log "  /etc/dcache/multi-mapfile"
cat <<'EOF' > /etc/dcache/multi-mapfile
username:tester uid:1000 gid:1000,true
username:admin  uid:0    gid:0,true
EOF

touch /etc/dcache/ban.conf


log "Generating self-signed host certificate..."
mkdir -p /etc/grid-security
touch /etc/grid-security/hostkey.pem
touch /etc/grid-security/hostcert.pem
mkdir -p /etc/grid-security/certificates
openssl genrsa 2048 > /etc/grid-security/hostkey.pem
openssl req -x509 -days 1000 -new \
            -subj "/C=NL/ST=Amsterdam/O=SURF/OU=ODS/CN=localhost" \
            -key /etc/grid-security/hostkey.pem \
            -out /etc/grid-security/hostcert.pem

log "  /etc/grid-security/storage-authzdb"
cat <<'EOF' > /etc/grid-security/storage-authzdb
version 2.1

authorize tester read-write 1000 1000 /home/tester /
authorize admin read-write 0 0 / /
EOF

log "Creating pools"
mkdir -p "${DATADIR}"
dcache pool create "${DATADIR}/pool-1" pool1 dCacheDomain
dcache pool create "${DATADIR}/tapepool-1" tapepool1 dCacheDomain


log "Running 'dcache database update' to lay out the database structures."
dcache database update

log "Creating directories in the dCache namespace"
# Create user home directories
chimera mkdir /home
chimera mkdir /home/tester
chimera chown 1000:1000 /home/tester
# Create tape test directory
chimera mkdir /home/tester
chimera mkdir /home/tester/tape
chimera chown 1000:1000 /home/tester/tape
chimera writetag /home/tester/tape hsmType osm
chimera writetag /home/tester/tape OSMTemplate 'StoreName generic'
chimera writetag /home/tester/tape sGroup tape
chimera writetag /home/tester/tape AccessLatency NEARLINE
chimera writetag /home/tester/tape RetentionPolicy CUSTODIAL


log "Starting dCache..."
systemctl daemon-reload
systemctl stop dcache.target
systemctl start dcache.target

# Loop until the dcache service is active
while ! systemctl is-active --quiet dcache.target; do
    for ((length=1; length<=10; length++)); do
        echo -ne "\rChecking if dcache service is started $(printf '%*s' "$length" '' | tr ' ' '*')"
        sleep 0.1
    done
done
log "dCache is running"

log "Waiting for admin interface to start"
count=0
max_count=20
false
while [ "$?" -ne "0" ]; do
    if nc -z localhost 22224 -w 1
    then
        log "Admin interface ready."
        break
    else
        sleep 1
       ((count++))
    fi
done

if [ $count -eq $max_count ]; then
    log "Admin interface did not become ready. Exit"
    exit 1
fi

# Create a function to easily access the admin interface
dcache-admin () {
  local service="$1"
  shift
  local command="$*"
  ssh -i $sshkey admin@localhost  -o "StrictHostKeyChecking no" -p 22224 "\s $service $command"
}

log "Trying to request PoolManager status from admin interface so check if it started correctly"
count=0
while [ $count -lt $max_count ]; do
    if dcache-admin PoolManager info 2>&1 | grep -q PoolUp; then
        log "Admin interface ready."
        break
    else
        sleep 1
       ((count++))
    fi
done

if [ $count -eq $max_count ]; then
    log "Unable to query PoolManager status via admin command. Exit"
    exit 1
fi

log "Preparing HSM script, for fake tape backend."
sed -e 's@puts URI.escape("hsm://#{instance}/?store=#{store}&group=#{group}&bfid=#{pnfsid}")@puts "hsm://#{instance}/?store=#{store}&group=#{group}&bfid=#{pnfsid}"@' \
    -i /usr/share/dcache/lib/hsmcp.rb
chmod 755 /usr/share/dcache/lib/hsmcp.rb

log "Check if tapepool1 is ready"
count=0
while [ $count -lt $max_count ]; do
    if dcache-admin tapepool1 info 2>&1 | grep -q "State : OPEN"; then
        log "tapepool1 ready."
        break
    else
        sleep 1
       ((count++))
    fi
done
if [ $count -eq $max_count ]; then
    log "Tapepool1 seems to having issues. Exit"
    exit 1
fi
log "Configuring tape pool"
dcache-admin "tapepool1" "hsm create -command=/usr/share/dcache/lib/hsmcp.rb -pnfs=/pnfs -hsmBase=${HSMBASE} -hsmInstance=osm -c:puts=1 -c:gets=1 -c:removes=1 osm"
# Pool configuration should be saved! Otherwise it vanishes after a restart.
dcache-admin "tapepool1" "save"

log "Preparing 'tape' directory"
chown dcache "$HSMBASE"
chmod 770 "$HSMBASE"

# Configure the tape pool in the PoolManager.
dcache-admin PoolManager "psu create unit -store generic:tape@osm"
dcache-admin PoolManager "psu create ugroup tape-ugroup"
dcache-admin PoolManager "psu addto ugroup tape-ugroup generic:tape@osm"
dcache-admin PoolManager "psu create pgroup tape-pools"
dcache-admin PoolManager "psu removefrom pgroup default tapepool1"
dcache-admin PoolManager "psu addto pgroup tape-pools tapepool1"
dcache-admin PoolManager "psu create link tape-link any-protocol tape-ugroup world-net"
dcache-admin PoolManager "psu set link tape-link -readpref=10 -writepref=10 -cachepref=10 -p2ppref=-1"
dcache-admin PoolManager "psu addto link tape-link tape-pools"
# dCache versions 9 and older need this setting
dcache-admin PoolManager "pm set -stage-allowed=yes'"
# In the PoolManager, we don't need to save changes: they are saved into Zookeeper.

#echo "Next step: write some PoolManager configuration."
#echo "Here is the default configuration:"
#echo '---------------------------------------------------'
#dcache-admin "PoolManager" "psu dump setup"
#echo '---------------------------------------------------'

echo
echo '---------------------------------------------------'
echo "This script has created a user for you:"
echo "Username: tester"
echo "Password: $PASSWD"
echo "The same password is used for the admin user of dCache"
echo
echo "Your admin console is available with the following command. You won't need a password. A ssh cert is used."
echo "ssh -p 22224 admin@localhost"
echo
echo "You can test uploading the README.md file with webdav now:"
echo "curl -k -v -u tester:$PASSWD -L -T README.md https://localhost:2880/home/tester/README.md"
echo
echo "Getting a macaroon authentication token:"
echo "curl -k -u tester:$PASSWD -X POST -H 'Content-Type: application/macaroon-request' -d '{ \"caveats\"  : [ \"path:/home/tester/\", \"activity:DOWNLOAD,LIST,UPLOAD,DELETE,MANAGE,READ_METADATA,UPDATE_METADATA\" ], \"validity\" : \"PT12H\" }' --fail https://localhost:2880/"
echo
echo "The api is available at: https://192.168.122.23:3880/api/v1/"
