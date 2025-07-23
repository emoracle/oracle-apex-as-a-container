# PRE          : Environment variables REGISTRY_USER and REGISTRY_PWD and SYS_PWD must exist
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

#-------------------------------------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------------------------------------

CONTAINER_NAME=${CONTAINER_NAME}         # The name of the container
SYS_PWD=${SYS_PWD}                       # Password of the db users
REGISTRY_USER=${REGISTRY_USER}           # Accountname for container-registry.oracle.com. Must be in an environment variable (export REGISTRY_USER="")
REGISTRY_PWD=${REGISTRY_PWD}             # Password of the registry. Must be in an environment variable (export REGISTRY_PWD="")
REGISTRY_TOKEN=${REGISTRY_TOKEN}         # Oauth2 token of the registry. Must be in an environment variable (export REGISTRY_TOKEN="")

PDB_NAME="FREEPDB1"                      # Name of the PDB
ADMIN_PWD=${ADMIN_PWD}                   # The passowrd of the admin-user within APEX

INSTALL_APEX_IN_IMAGE=${INSTALL_APEX}    # Install APEX
INSTALL_ORDS_IN_IMAGE=${INSTALL_ORDS}    # Install ORDS
#-------------------------------------------------------------------------------------------------------------
# Main script 
#-------------------------------------------------------------------------------------------------------------

# Check of Docker is running

if ! docker info > /dev/null 2>&1; then
  echo "ERROR: Docker is not running. Start Docker and try again."
  exit 1
fi

# Check on environment variables

if [ -z "$REGISTRY_USER" ] || [ -z "$SYS_PWD" ] || [ -z "$CONTAINER_NAME" ]; then
  echo "ERROR: Environment variables REGISTRY_USER, SYS_PWD and CONTAINER_NAME must be set."
  exit 1
fi

# Login to the registry of Oracle

echo "$REGISTRY_TOKEN" | docker login container-registry.oracle.com --username "$REGISTRY_USER" --password-stdin

# Retrieve the image of the latest version of the Oracle database

docker pull container-registry.oracle.com/database/free:latest

# We start the container and check on availability

if ! docker ps --filter "name=$CONTAINER_NAME" --filter "status=running"| grep -w $CONTAINER_NAME > /dev/null; then
  echo "Container $CONTAINER_NAME is not running. Starting it now..."
  docker run -d -it --name $CONTAINER_NAME -p 1521:1521 -p 5500:5500 -p 8080:8080 -p 8443:8443 -e ORACLE_PWD=$SYS_PWD container-registry.oracle.com/database/free:latest
else
  echo "Container $CONTAINER_NAME is already running."
fi

COUNTER=0
docker exec $CONTAINER_NAME /opt/oracle/checkDBStatus.sh > /dev/null 2>&1
STATUS=$?

while [ $STATUS -ne 0 ]; do
  COUNTER=$((COUNTER + 1))

  printf "\r$STATUS $CONTAINER_NAME Check for availability database... cycle: %d" $COUNTER
  sleep  10

  docker exec $CONTAINER_NAME /opt/oracle/checkDBStatus.sh > /dev/null 2>&1
  STATUS=$?
done
 
# Installing APEX
if [ "$INSTALL_APEX_IN_IMAGE" = "FALSE" ]; then
  echo " "
  echo "We DO NOT install APEX and ORDS."
  echo "Database name : " "$PDB_NAME"
  exit 0
fi

# Open a shell on the image

docker exec -i $CONTAINER_NAME bash << EOF

if [ -d "/home/oracle/apex" ]; then
  echo "apex directory already exists. Installation of APEX will be skipped."
else
  curl -o apex-latest.zip https://download.oracle.com/otn_software/apex/apex-latest.zip

  unzip apex-latest.zip

  cd apex

  echo "ALTER SESSION SET CONTAINER = $PDB_NAME;
  @apexins.sql SYSAUX SYSAUX TEMP /i/
  ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
  ALTER USER APEX_PUBLIC_USER IDENTIFIED BY $SYS_PWD;
  exit" | sqlplus / as sysdba
fi 

EOF

init_dir="./init"
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

docker cp ./init/ $CONTAINER_NAME:/home/oracle/init/

# Change the password of the admin user in APEX

docker exec -i $CONTAINER_NAME bash << EOF

cd apex

echo "ALTER SESSION SET CONTAINER = $PDB_NAME;
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
 

docker exec -i $CONTAINER_NAME bash << EOF
mkdir -p /home/oracle/scripts

cd /home/oracle/

su

rm -rf /home/oracle/init

cd /etc/yum/vars

rm -f ociregion

touch ociregion

dnf update

dnf install sudo -y

if sudo grep -q "^oracle[[:space:]]" /etc/sudoers || sudo grep -q "^oracle[[:space:]]" /etc/sudoers.d/*; then
    echo "User oracle already has sudo privileges."
else
    echo "oracle ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers
fi

dnf install java-17-openjdk -y

mkdir -p /etc/ords
mkdir -p /etc/ords/config
mkdir -p /home/oracle/logs
chmod -R 777 /etc/ords
java -version

yum-config-manager --add-repo=http://yum.oracle.com/repo/OracleLinux/OL8/oracle/software/x86_64
dnf install ords -y

export _JAVA_OPTIONS="-Xms512M -Xmx512M"

echo $SYS_PWD > /home/oracle/ww.txt
echo $SYS_PWD >> /home/oracle/ww.txt
echo $SYS_PWD >> /home/oracle/ww.txt
echo $SYS_PWD >> /home/oracle/ww.txt

ords --config /etc/ords/config install \
--admin-user SYS \
--db-hostname localhost \
--db-port 1521 \
--db-servicename FREEPDB1 \
--feature-db-api true \
--feature-rest-enabled-sql true \
--feature-sdw true \
--password-stdin < /home/oracle/ww.txt

rm -f ww.txt

EOF

# Creating a startscript

docker exec -i $CONTAINER_NAME bash << 'EOFMAIN'

cat > /home/oracle/scripts/start_ords.sh << 'EOF'
export ORDS_HOME=/usr/local/bin/ords
export _JAVA_OPTIONS="-Xms512M -Xmx512M"

LOGFILE=/home/oracle/logs/ords-$(date +"%Y%m%d").log

nohup ${ORDS_HOME} --config /etc/ords/config serve --apex-images /home/oracle/apex/images >> $LOGFILE 2>&1 & echo "View log file with : tail -f $LOGFILE"

EOF
EOFMAIN

# Creating a stopscript

docker exec -i $CONTAINER_NAME bash << 'EOFMAIN' 
cat > /home/oracle/scripts/stop_ords.sh << 'EOF'

kill $(ps -ef | grep [o]rds.war | awk '{print $2}')

EOF
EOFMAIN

# Creating a autostartscript

docker exec -i $CONTAINER_NAME bash << EOFMAIN
cat >  /opt/oracle/scripts/startup/01_auto_ords.sh << EOF

sudo sh /home/oracle/scripts/start_ords.sh

EOF
EOFMAIN

# Cleaning up

docker exec -i $CONTAINER_NAME bash << 'EOF'
su 

rm apex-latest.zip

$ORACLE_HOME/bin/oraversion -compositeVersion > /opt/oracle/oradata/version.txt

EOF

docker restart $CONTAINER_NAME

echo "Ready creating the container"
echo "Check with http://localhost:8080/ords"

# Wait a while before checking the URL

sleep 20

HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://localhost:8080/ords/_/landing)

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "The URL can be reached. "
    echo "The SYS password for this container is $SYS_PWD"
    echo "The password within APEX is $ADMIN_PWD"
else
    echo "The URL can not be reached. HTTP status code: $HTTP_STATUS"
fi

echo "Database name : " "$PDB_NAME"
