# Auteur       : H.E. van Meerendonk
# Creation date: 01-09-2023
# Revisie      : 

CONTAINER_NAME="ems-an-db"
REPOSITORY="juva/apex-db-ords"
VERSIE=$(date +"%Y%m%d%H%M")

echo "commit $CONTAINER_NAME naar fra.ocir.io/juva2oca/$REPOSITORY:$VERSIE"
docker commit $CONTAINER_NAME fra.ocir.io/juva2oca/$REPOSITORY:$VERSIE

echo "login naar de repository"
docker login fra.ocir.io -u "juva2oca/DevOps-OCI" -p "t6y05L+L3P8CAHw:rPo)"

echo "push naar de repository"
docker pull fra.ocir.io/juva2oca/$REPOSITORY:$VERSIE
if [ $? -ne 0 ]; then
  docker push fra.ocir.io/juva2oca/$REPOSITORY:$VERSIE
fi 
