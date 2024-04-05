export REGISTRY_USER="vanmeerendonk@gmail.com"
export REGISTRY_PWD="Ocp4505pin"
export SYS_PWD="JuvaDBSYS123##"
export CONTAINER_NAME="ems-an-db"
export ADMIN_PWD="Welcome_1"

rm -f install.log

./maak_container_free.sh 2>&1 | tee install.log
