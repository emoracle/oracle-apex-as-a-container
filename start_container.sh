export REGISTRY_USER="vanmeerendonk@gmail.com"
export REGISTRY_PWD="*******"
export SYS_PWD="*****##"
export CONTAINER_NAME="ems-an-db"
export ADMIN_PWD="Welcome_1"

rm -f install.log

./maak_container_free.sh 2>&1 | tee install.log
