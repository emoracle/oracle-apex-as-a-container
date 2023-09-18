# oracle-apex-as-a-container
An Oracle Free DB with Oracle APEX installed an with ORDS listening on 8080 in one container

Standing on the shoulders of https://pretius.com/blog/oracle-apex-docker-ords/

## Creating a running container

### maak_container_free.sh
This bash-file 
- pulls and instantiate the latest Oracle Free DB from container-registry.oracle.com
- installs the latest APEX installation on the container
- installs the latest ORDS software on the container

The resulting container has a working Oracle APEX installation running on http://localhost:8080

## Pushing to the repository
You can push this to an Oracle Container Registry in OCI. 
Here I use frankfurt (fra.ocir.io)

The running container should be committed and tagged with the proper tag

docker commit $CONTAINER_NAME fra.ocir.io/$TENANT/$REPOSITORY:$VERSION
docker login fra.ocir.io

docker push fra.ocir.io/$TENANT/$REPOSITORY:$VERSION

## Deploying on Oracle Kubernetes Engine (OKE)

To deploy the database on a OKE kluster you could use
### k8s_apex_deploy.yaml
This creates a Persistant volume claim on a Filesystem that should already be present
It creates a deployment and so a pod as instantiation of the image
It creates a CLusterIP service on port 1521 (database) and 8080 (ords)


# Developed on:
WSL2

Docker-Desktop
