# oracle-apex-as-a-container
An Oracle Free DB with Oracle APEX installed an with ORDS listening on 8080 in one container

## Creating a running container

### maak_container_free.sh
This bash-file 
- pulls and instantiate the latest Oracle Free DB from container-registry.oracle.com
- installs the latest APEX installation on the container
- installs the latest ORDS software on the container

The resulting container has a working Oracle APEX installation running on http://localhost:8080

## Pushing to the repository
I am working with Oracle Container Registry in OCI. 
Here I use frankfurt.

The running container should be committed and tagged with the proper tag

docker commit $CONTAINER_NAME fra.ocir.io/$TENANT/$REPOSITORY:$VERSION
docker login fra.ocir.io

docker push fra.ocir.io/$TENANT/$REPOSITORY:$VERSION

# Developed on:
WSL2

Docker-Desktop
