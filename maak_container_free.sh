# PRE          : Er dienen environment variabelen REGISTRY_USER en REGISTRY_PWD en SYS_PWD te bestaan
#                om te connecteren naar container-registry.oracle.com en als ww binnen de image
# Auteur       : H.E. van Meerendonk
# Creation date: 01-09-2023
# Revisie      : 
# 15-11-2023 Controleer of Docker draait
# 21-11-2023 Aanbrengen dynamische hook zodat via een init.sql script een applicatie met objecten
#            gelijk aangebracht kan worden.
#            Backticks vervangen door $()
#            Weggooien via rm -rf

#-------------------------------------------------------------------------------------------------------------
# Configuratie
#-------------------------------------------------------------------------------------------------------------

CONTAINER_NAME=${CONTAINER_NAME}         # De naam van de container
SYS_PWD=${SYS_PWD}                       # Wachtwoord van de db users
REGISTRY_USER=${REGISTRY_USER}           # Accountnaam voor container-registry.oracle.com. Moet in een environvariabele staan (export REGISTRY_USER="")
REGISTRY_PWD=${REGISTRY_PWD}             # Bijbehorende wachtwoord. Moet ook in de environment staan

PDB_NAAM="FREEPDB1"                      # Naam van de PDB
ADMIN_PWD=${ADMIN_PWD}                   # Het wachtwoord van de admin-user van APEX

#-------------------------------------------------------------------------------------------------------------
# Main script 
#-------------------------------------------------------------------------------------------------------------

# Controleer of docker aan staat

if ! docker info > /dev/null 2>&1; then
  echo "ERROR: Docker draait niet. Start Docker en probeer opnieuw."
  exit 1
fi

# Controleer op environment variabelen

if [ -z "$REGISTRY_USER" ] || [ -z "$SYS_PWD" ] || [ -z "$CONTAINER_NAME" ]; then
  echo "ERROR: Omgevingsvariabelen zijn niet gezet. Het script stopt."
  exit 1
fi

# Controleer op environment variabelen

if [ -z "$REGISTRY_USER" ] || [ -z "$SYS_PWD" ] || [ -z "$CONTAINER_NAME" ]; then
  echo "ERROR: Omgevingsvariabelen zijn niet gezet. Het script stopt." 
  exit 1
fi

# Inloggen in de Reporitory van Oracle

docker login container-registry.oracle.com --username $REGISTRY_USER --password $REGISTRY_PWD

#We halen de laatste database op

docker pull container-registry.oracle.com/database/free:latest

# We starten de container en check op beschikbaarheid

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

  printf "\r$STATUS $CONTAINER_NAME Controleren op beschikbaarheid database... cycle: %d" $COUNTER
  sleep  10

  docker exec $CONTAINER_NAME /opt/oracle/checkDBStatus.sh > /dev/null 2>&1
  STATUS=$?
done
 
# Installeren van APEX

# Open een shell op de image

docker exec -i $CONTAINER_NAME bash << EOF

if [ -d "/home/oracle/apex" ]; then
  echo "apex directory bestaat al. We slaan de installatie van apex over"
else
  curl -o apex-latest.zip https://download.oracle.com/otn_software/apex/apex-latest.zip

  unzip apex-latest.zip

  cd apex

  echo "ALTER SESSION SET CONTAINER = $PDB_NAAM;
  @apexins.sql SYSAUX SYSAUX TEMP /i/
  ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
  ALTER USER APEX_PUBLIC_USER IDENTIFIED BY $SYS_PWD;
  exit" | sqlplus / as sysdba
fi 

EOF

init_dir="./init"
init_sql="$init_dir/init.sql"

if [ ! -d "$init_dir" ]; then
   # Hook directory bestaat niet, we maken hem aan
    mkdir -p "$init_dir"
    echo "Created directory $init_dir."
fi

if [ ! -f "$init_sql" ]; then
    # Hook bestand bestaat niet. We maken een dummy aan
    echo "select sysdate from dual;" > "$init_sql"
    echo "Created $init_sql with default content."
fi

#copieer alles uit init directory naar de container

docker cp ./init/ $CONTAINER_NAME:/home/oracle/init/

# Verander het wachtwoord van de ADMIN user
# en start de hook op

docker exec -i $CONTAINER_NAME bash << EOF

cd apex

echo "ALTER SESSION SET CONTAINER = $PDB_NAAM;
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

# Installeren van ORDS. Dit is inherent herstartbaar

docker exec -i $CONTAINER_NAME bash << EOF
mkdir -p /home/oracle/scripts

cd /home/oracle/

su

rm -rf /home/oracle/init

dnf update

dnf install sudo -y

if sudo grep -q "^oracle[[:space:]]" /etc/sudoers || sudo grep -q "^oracle[[:space:]]" /etc/sudoers.d/*; then
    echo "User oracle heeft al sudo privileges."
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

# We maken een startscript 

docker exec -i $CONTAINER_NAME bash << 'EOFMAIN'

cat > /home/oracle/scripts/start_ords.sh << 'EOF'
export ORDS_HOME=/usr/local/bin/ords
export _JAVA_OPTIONS="-Xms512M -Xmx512M"

LOGFILE=/home/oracle/logs/ords-$(date +"%Y%m%d").log

nohup ${ORDS_HOME} --config /etc/ords/config serve --apex-images /home/oracle/apex/images >> $LOGFILE 2>&1 & echo "View log file with : tail -f $LOGFILE"

EOF
EOFMAIN

# We maken een stopscript 

docker exec -i $CONTAINER_NAME bash << 'EOFMAIN' 
cat > /home/oracle/scripts/stop_ords.sh << 'EOF'

kill $(ps -ef | grep [o]rds.war | awk '{print $2}')

EOF
EOFMAIN

# We maken een autostart

docker exec -i $CONTAINER_NAME bash << EOFMAIN
cat >  /opt/oracle/scripts/startup/01_auto_ords.sh << EOF

sudo sh /home/oracle/scripts/start_ords.sh

EOF
EOFMAIN

# We ruimen de boel op 

docker exec -i $CONTAINER_NAME bash << 'EOF'
su 

rm apex-latest.zip

$ORACLE_HOME/bin/oraversion -compositeVersion > /opt/oracle/oradata/version.txt

EOF

docker restart $CONTAINER_NAME

echo "Klaar met het aanmaken van een container"
echo "Controleer met http://localhost:8080/ords"

# Wacht even 

sleep 20

HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://localhost:8080/ords/_/landing)

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "De URL is bereikbaar. "
    echo "Het SYS wachtwoord voor deze container is $SYS_PWD"
    echo "Het wachtwoord binnen APEX is $ADMIN_PWD"
else
    echo "De URL is niet bereikbaar. HTTP status code: $HTTP_STATUS"
fi
