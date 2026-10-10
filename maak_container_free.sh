#!/usr/bin/env bash

# PRE          : Environment variables REGISTRY_USER, REGISTRY_TOKEN and SYS_PWD must exist
#                to connect to container-registry.oracle.com and as the password within the image
# Auteur       : H.E. van Meerendonk
# Creation date: 01-09-2023
# Revisie      : 
# 15-11-2023 HEM Check if docker is running
# 21-11-2023 HEM Applying dynamic hook so that an application with objects can be created using an init.sql script.
#            Replacing backticks with $()
#            Deleting using rm -rf
# 18-05-2024 HEM Changes Linux 8.9 with 23ai. INSTALL_* SWITCHES added for conveniance
# 19-05-2024 HEM Clearing ociregions: -us-phoenix is not responding
# 17-07-2025 HEM Token authentication and STDIN for docker login
# 23-07-2025 HEM  not in Dutch

set -Eeuo pipefail

trap 'printf "ERROR: Installation failed at line %s.\n" "$LINENO" >&2' ERR

#-------------------------------------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------------------------------------

CONTAINER_NAME=${CONTAINER_NAME:-}       # The name of the container
SYS_PWD=${SYS_PWD:-}                     # Password of the db users
REGISTRY_USER=${REGISTRY_USER:-}         # Account name for container-registry.oracle.com
REGISTRY_TOKEN=${REGISTRY_TOKEN:-}       # OAuth2 token for container-registry.oracle.com

PDB_NAME="FREEPDB1"                      # Name of the PDB
ADMIN_PWD=${ADMIN_PWD:-}                 # The password of the admin user within APEX

INSTALL_APEX_IN_IMAGE=${INSTALL_APEX:-}  # Install APEX
INSTALL_ORDS_IN_IMAGE=${INSTALL_ORDS:-}  # Install ORDS
DB_MAX_ATTEMPTS=${DB_MAX_ATTEMPTS:-60}
DB_RETRY_SECONDS=${DB_RETRY_SECONDS:-10}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_value() {
  local name=$1
  local value=$2
  [[ -n "$value" ]] || die "Environment variable $name must be set."
}

validate_boolean() {
  local name=$1
  local value=$2
  [[ "$value" == "TRUE" || "$value" == "FALSE" ]] || \
    die "$name must be either TRUE or FALSE."
}

validate_positive_integer() {
  local name=$1
  local value=$2
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || die "$name must be a positive integer."
}

validate_password() {
  local name=$1
  local value=$2
  [[ "$value" =~ ^[A-Za-z0-9_@%+.,:#\!\?-]+$ ]] || \
    die "$name contains unsupported characters. Use letters, digits, or _@%+.,:#!?- only."
}

# Treat upstream diagnostics as sensitive too (SQLPlus can echo failing SQL).
# Quote the replacement pattern so token punctuation is matched literally.
redact_output() {
  local line secret part i j swap
  local -a secrets=()
  for secret in "$REGISTRY_TOKEN" "$SYS_PWD" "$ADMIN_PWD" "${REGISTRY_PWD:-}"; do
    while IFS= read -r part || [[ -n "$part" ]]; do
      [[ -z "$part" ]] || secrets+=("$part")
    done <<< "$secret"
  done
  # Mask the longest value first when credentials share a prefix/sub-string.
  for ((i=0; i<${#secrets[@]}; i++)); do
    for ((j=i+1; j<${#secrets[@]}; j++)); do
      if (( ${#secrets[j]} > ${#secrets[i]} )); then
        swap=${secrets[i]}
        secrets[i]=${secrets[j]}
        secrets[j]=$swap
      fi
    done
  done
  while IFS= read -r line || [[ -n "$line" ]]; do
    for secret in "${secrets[@]}"; do
      line=${line//"$secret"/[REDACTED]}
    done
    printf '%s\n' "$line"
  done
}

run_installation() (
#-------------------------------------------------------------------------------------------------------------
# Main script 
#-------------------------------------------------------------------------------------------------------------

# Validate configuration before invoking Docker

require_value REGISTRY_USER "$REGISTRY_USER"
require_value REGISTRY_TOKEN "$REGISTRY_TOKEN"
require_value SYS_PWD "$SYS_PWD"
require_value CONTAINER_NAME "$CONTAINER_NAME"
require_value INSTALL_APEX "$INSTALL_APEX_IN_IMAGE"
require_value INSTALL_ORDS "$INSTALL_ORDS_IN_IMAGE"

validate_boolean INSTALL_APEX "$INSTALL_APEX_IN_IMAGE"
validate_boolean INSTALL_ORDS "$INSTALL_ORDS_IN_IMAGE"
validate_positive_integer DB_MAX_ATTEMPTS "$DB_MAX_ATTEMPTS"
validate_positive_integer DB_RETRY_SECONDS "$DB_RETRY_SECONDS"
validate_password SYS_PWD "$SYS_PWD"

[[ "$CONTAINER_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || \
  die "CONTAINER_NAME must start with an alphanumeric character and may only contain letters, digits, underscores, periods and dashes."

if [[ "$INSTALL_ORDS_IN_IMAGE" == "TRUE" && "$INSTALL_APEX_IN_IMAGE" != "TRUE" ]]; then
  die "INSTALL_ORDS=TRUE requires INSTALL_APEX=TRUE."
fi

if [[ "$INSTALL_APEX_IN_IMAGE" == "TRUE" ]]; then
  require_value ADMIN_PWD "$ADMIN_PWD"
  validate_password ADMIN_PWD "$ADMIN_PWD"
fi

command -v docker >/dev/null 2>&1 || die "Docker is not installed or is not on PATH."
command -v curl >/dev/null 2>&1 || die "curl is not installed or is not on PATH."

# Check if Docker is running

docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker and try again."

# Login to the registry of Oracle

printf '%s\n' "$REGISTRY_TOKEN" | docker login container-registry.oracle.com --username "$REGISTRY_USER" --password-stdin

# Retrieve the image of the latest version of the Oracle database

docker pull container-registry.oracle.com/database/free:latest

# We start the container and check on availability

if docker ps --filter "name=^/${CONTAINER_NAME}$" --filter "status=running" --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  echo "Container $CONTAINER_NAME is already running."
elif docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  echo "Container $CONTAINER_NAME exists but is stopped. Starting it now..."
  docker start "$CONTAINER_NAME" >/dev/null
else
  echo "Container $CONTAINER_NAME is not running. Starting it now..."
  docker run -d -it --name "$CONTAINER_NAME" -p 1521:1521 -p 8080:8080 -p 8443:8443 -e "ORACLE_PWD=$SYS_PWD" container-registry.oracle.com/database/free:latest >/dev/null
fi

COUNTER=0
while ! docker exec "$CONTAINER_NAME" /opt/oracle/checkDBStatus.sh >/dev/null 2>&1; do
  COUNTER=$((COUNTER + 1))
  if (( COUNTER >= DB_MAX_ATTEMPTS )); then
    die "Database did not become available after $((DB_MAX_ATTEMPTS * DB_RETRY_SECONDS)) seconds."
  fi
  printf '%s Check for database availability... cycle: %d/%d\n' "$CONTAINER_NAME" "$COUNTER" "$DB_MAX_ATTEMPTS"
  sleep "$DB_RETRY_SECONDS"
done
printf '\nDatabase is available.\n'
 
# Installing APEX
if [ "$INSTALL_APEX_IN_IMAGE" = "FALSE" ]; then
  echo " "
  echo "We DO NOT install APEX and ORDS."
  echo "Database name : " "$PDB_NAME"
  exit 0
fi

# Open a shell on the image

docker exec -i "$CONTAINER_NAME" bash -seuo pipefail << EOF

if [ -d "/home/oracle/apex" ]; then
  echo "apex directory already exists. Installation of APEX will be skipped."
else
  curl --fail --location --show-error -o apex-latest.zip https://download.oracle.com/otn_software/apex/apex-latest.zip

  unzip apex-latest.zip

  cd apex

  echo "whenever oserror exit failure
  whenever sqlerror exit sql.sqlcode
  ALTER SESSION SET CONTAINER = $PDB_NAME;
  @apexins.sql SYSAUX SYSAUX TEMP /i/
  ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
  ALTER USER APEX_PUBLIC_USER IDENTIFIED BY \"$SYS_PWD\";
  exit" | sqlplus / as sysdba
fi 

EOF

init_dir="${INIT_DIR:-$SCRIPT_DIR/build/init}"
init_sql="$init_dir/init.sql"

if [ ! -d "$init_dir" ]; then
   # Hook directory does not exist. We create it
    mkdir -p "$init_dir"
    echo "Created directory $init_dir."
fi

if [ ! -f "$init_sql" ]; then
    # Hook file does not exist. We create it. 
    echo "select sysdate from dual;" > "$init_sql"
    echo "Created $init_sql with default content."
fi

# Copy everything in the init directory to the container

docker cp "$init_dir/." "$CONTAINER_NAME:/home/oracle/init/"

# Change the password of the admin user in APEX

docker exec -i "$CONTAINER_NAME" bash -seuo pipefail << EOF

cd apex

echo "whenever oserror exit failure
whenever sqlerror exit sql.sqlcode
ALTER SESSION SET CONTAINER = $PDB_NAME;
@@core/scripts/set_appun.sql

alter session set current_schema = &APPUN;

col user_id       noprint new_value M_USER_ID
col email_address noprint new_value M_EMAIL_ADDRESS
set termout off
select rtrim(min(user_id))                        as user_id
,      nvl ( rtrim(min(email_address)), 'ADMIN' ) as email_address
from   wwv_flow_fnd_user
where  security_group_id = 10
and    user_name         = 'ADMIN'
/
set termout on
begin
  if length('&M_USER_ID.') > 0 
  then
    sys.dbms_output.put_line('User "ADMIN" exists.');
  else
    sys.dbms_output.put_line('User "ADMIN" does not yet exist and will be created.');
  end if;
end;
/

variable PASSWORD varchar2(128)

create or replace procedure wwv_flow_assign_pwd 
  ( p_dest out varchar2
  , p_src  in  varchar2 
  )
is
begin
  p_dest := p_src;
end wwv_flow_assign_pwd;
/

alter session set cursor_sharing=force;

call wwv_flow_assign_pwd(:PASSWORD,'$ADMIN_PWD');

alter session set cursor_sharing=exact;

drop procedure wwv_flow_assign_pwd;

declare
  c_user_id  constant number         := to_number( '&M_USER_ID.' );
  c_username constant varchar2(4000) := 'ADMIN';
  c_email    constant varchar2(4000) := 'a@b.nl';
  c_password constant varchar2(4000) := :PASSWORD;

  c_old_sgid constant number := wwv_flow_security.g_security_group_id;
  c_old_user constant varchar2(255) := wwv_flow_security.g_user;

  procedure cleanup
  is
  begin
    wwv_flow_security.g_security_group_id := c_old_sgid;
    wwv_flow_security.g_user              := c_old_user;
  end cleanup;
begin
  wwv_flow_security.g_security_group_id := 10;
  wwv_flow_security.g_user              := c_username;

  wwv_flow_fnd_user_int.create_or_update_user
    ( p_user_id  => c_user_id
    , p_username => c_username
    , p_email    => c_email
    , p_password => c_password 
    );

  commit;
  cleanup();
exception
  when others 
  then
    cleanup();
    raise;
end;
/

Prompt Start het root-script init.sql

@/home/oracle/init/init.sql

exit
" | sqlplus / as sysdba

EOF

# Installing ORDS

if [ "$INSTALL_ORDS_IN_IMAGE" = "FALSE" ]; then
  echo "ORDS is not being installed."
  exit 0;
fi 
 

docker exec --user root -i "$CONTAINER_NAME" bash -seuo pipefail << EOF
mkdir -p /home/oracle/scripts

cd /home/oracle/

rm -rf /home/oracle/init

cd /etc/yum/vars

rm -f ociregion

touch ociregion

dnf update -y

dnf install java-17-openjdk -y

mkdir -p /etc/ords
mkdir -p /etc/ords/config
mkdir -p /home/oracle/logs
chown -R oracle:oinstall /home/oracle/scripts /home/oracle/logs
java -version

yum-config-manager --add-repo=http://yum.oracle.com/repo/OracleLinux/OL8/oracle/software/x86_64
dnf install ords -y

export _JAVA_OPTIONS="-Xms512M -Xmx512M"

printf '%s\n%.0s' "$SYS_PWD" {1..4} | \
ords --config /etc/ords/config install \
--admin-user SYS \
--db-hostname localhost \
--db-port 1521 \
--db-servicename FREEPDB1 \
--feature-db-api true \
--feature-rest-enabled-sql true \
--feature-sdw true \
--password-stdin 

chown -R oracle:oinstall /etc/ords
find /etc/ords -type d -exec chmod 750 {} +
find /etc/ords -type f -exec chmod 640 {} +

EOF

# Creating a startscript

docker exec -i "$CONTAINER_NAME" bash -seuo pipefail << 'EOFMAIN'

cat > /home/oracle/scripts/start_ords.sh << 'EOF'
export ORDS_HOME=/usr/bin/ords
export _JAVA_OPTIONS="-Xms512M -Xmx512M"

LOGFILE=/home/oracle/logs/ords-$(date +"%Y%m%d").log

nohup ${ORDS_HOME} --config /etc/ords/config serve --apex-images /home/oracle/apex/images >> $LOGFILE 2>&1 & echo "View log file with : tail -f $LOGFILE"

EOF
EOFMAIN

# Creating a stopscript

docker exec -i "$CONTAINER_NAME" bash -seuo pipefail << 'EOFMAIN'
cat > /home/oracle/scripts/stop_ords.sh << 'EOF'

kill $(ps -ef | grep [o]rds.war | awk '{print $2}')

EOF
EOFMAIN

# Creating a autostartscript

docker exec -i "$CONTAINER_NAME" bash -seuo pipefail << 'EOFMAIN'
cat > /opt/oracle/scripts/startup/01_auto_ords.sh << 'EOF'

if [ "$(id -u)" -eq 0 ]; then
  runuser -u oracle -- sh /home/oracle/scripts/start_ords.sh
else
  sh /home/oracle/scripts/start_ords.sh
fi

EOF
EOFMAIN

# Cleaning up

docker exec --user root -i "$CONTAINER_NAME" bash -seuo pipefail << 'EOF'
rm -f apex-latest.zip

$ORACLE_HOME/bin/oraversion -compositeVersion > /opt/oracle/oradata/version.txt

EOF

docker restart "$CONTAINER_NAME" >/dev/null

echo "Ready creating the container"
echo "Check with http://localhost:8080/ords"

# Wait a while before checking the URL
URL="http://localhost:8080/ords/_/landing"
MAX_ATTEMPTS=30        # At most 10 seconds per request plus 10 seconds between retries
SLEEP_SECONDS=10       # wait between retries

echo "Checking ORDS endpoint at $URL ..."
for ((i=1; i<=MAX_ATTEMPTS; i++)); do
  if ! HTTP_STATUS=$(curl --connect-timeout 5 --max-time 10 \
      --output /dev/null --silent --write-out "%{http_code}" "$URL"); then
    HTTP_STATUS=000
  fi
  HTTP_STATUS=${HTTP_STATUS:-000}

  if [[ "$HTTP_STATUS" == "200" ]]; then
    echo -e "\n ORDS is up (HTTP 200)."
    echo "Database name: $PDB_NAME"
    break
  fi

  printf 'Attempt %02d/%02d — status %s ...\n' "$i" "$MAX_ATTEMPTS" "$HTTP_STATUS"
  if (( i < MAX_ATTEMPTS )); then
    sleep "$SLEEP_SECONDS"
  fi
done

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo -e "\n ORDS did not respond with HTTP 200 after $MAX_ATTEMPTS attempts (request timeout: 10 seconds)."
  exit 1
fi

echo "End of the installation. The container is ready to use."  
echo "You can now connect to the database using the following command:"
echo "sqlplus sys@//localhost:1521/$PDB_NAME as sysdba"
echo "Enter the database password when SQL*Plus prompts for it."
echo "You can also connect to APEX using the following URL:"
echo "http://localhost:8080/ords/apex"
echo "You can also connect to ORDS using the following URL:"
echo "http://localhost:8080/ords/_/landing"
)

# A subshell keeps early exits local; pipefail preserves installation failures.
run_installation "$@" 2>&1 | redact_output
