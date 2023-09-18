# PRE         : Er dienen environment variabelen REGISTRY_USER en REGISTRY_PWD en SYS_PWD te bestaan
#               om te connecteren naar container-registry.oracle.com en als ww binnen de image
# Auteur       : H.E. van Meerendonk
# Creation date: 01-09-2023
# Revisie      : 

#-------------------------------------------------------------------------------------------------------------
# Configuratie
#-------------------------------------------------------------------------------------------------------------

CONTAINER_NAME=${CONTAINER_NAME}         # De naam van de container
SYS_PWD=${SYS_PWD}                       # Wachtwoord van de db users
REGISTRY_USER=${REGISTRY_USER}           # Accountnaam voor container-registry.oracle.com. Moet in een environvariabele staan ( export REGISTRY_USER="")
REGISTRY_PWD=${REGISTRY_PWD}             # Bijbehorende wachtwoord. Moet ook in de environment staan
PDB_NAAM="FREEPDB1"

#-------------------------------------------------------------------------------------------------------------
# Main script 
#-------------------------------------------------------------------------------------------------------------

# Controleer op environment variabelen
if [ -z "$REGISTRY_USER" ] || [ -z "$SYS_PWD" ] || [ -z "$CONTAINER_NAME" ]; then
  echo "ERROR: Omgevingsvariabelen zijn niet gezet. Het script stopt." 
  exit 1
fi

# Inloggen in de Reporitory van Oracle
docker login container-registry.oracle.com --username $REGISTRY_USER --password $REGISTRY_PWD

#We halen de laatste data base op
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

# Installeren van ORDS. DIt is inherent herstartbaar

docker exec -i $CONTAINER_NAME bash << EOF
mkdir -p /home/oracle/software
mkdir -p /home/oracle/software/apex
mkdir -p /home/oracle/software/ords
mkdir -p /home/oracle/scripts

cp -r /home/oracle/apex/images /home/oracle/software/apex

cd /home/oracle/

su

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

LOGFILE=/home/oracle/logs/ords-`date +"%Y""%m""%d"`.log

nohup ${ORDS_HOME} --config /etc/ords/config serve --apex-images /home/oracle/software/apex/images >> $LOGFILE 2>&1 & echo "View log file with : tail -f $LOGFILE"
docker exec -i $CONTAINER_NAME bash << EOFMAIN
cat > /home/oracle/scripts/stop_ords.sh << 'EOF'

kill `ps -ef | grep [o]rds.war | awk '{print $2}'`

EOF

EOFMAIN

# We maken een stopscript 

docker exec -i $CONTAINER_NAME bash << 'EOFMAIN' 
cat > /home/oracle/scripts/stop_ords.sh << 'EOF'

kill `ps -ef | grep [o]rds.war | awk '{print $2}'`

EOF
EOFMAIN

# We maken een autostart
docker exec -i $CONTAINER_NAME bash << EOFMAIN
cat >  /opt/oracle/scripts/startup/01_auto_ords.sh << EOF

sudo sh /home/oracle/scripts/start_ords.sh

EOF
EOFMAIN

docker restart $CONTAINER_NAME

echo "Klaar met het aanmaken van een container"
echo "Controleer met http://localhost:8080/ords"

HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://localhost:8080/ords/_/landing)

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "De URL is bereikbaar. "
else
    echo "De URL is niet bereikbaar. HTTP status code: $HTTP_STATUS"
fi

