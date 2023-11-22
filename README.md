# oracle-apex-as-a-container
An Oracle Free DB with Oracle APEX installed an with ORDS listening on 8080 in one container

Standing on the shoulders of https://pretius.com/blog/oracle-apex-docker-ords/

## Creating a running container

### maak_container_free.sh
This bash-file 
- pulls and instantiate the latest Oracle Free DB from container-registry.oracle.com
- installs the latest APEX installation on the container
- installs your sql-statements (e.g. for creating a user, workspace e.a.)
- installs the latest ORDS software on the container

The resulting container has a working Oracle APEX installation running on http://localhost:8080
The initial password for the ADMIN user on the INTERNAL workspace is set to Welcome_1.
I recommend opening a terminal to the container and 
~~~
cd apex
sqlplus / as sysdba
@apxchpwd
~~~

## Pushing to the repository
You can push this to an Oracle Container Registry in OCI. 
Here I use frankfurt (fra.ocir.io)

The running container should be committed and tagged with the proper tag
~~~
docker commit $CONTAINER_NAME fra.ocir.io/$TENANT/$REPOSITORY:$VERSION
docker login fra.ocir.io
docker push fra.ocir.io/$TENANT/$REPOSITORY:$VERSION
~~~

## Deploying on Oracle Kubernetes Engine (OKE)

To deploy the image as a pod on a OKE kluster you could use 
~~~
kubectl apply -f k8s_fullapex_deploy.yaml 
~~~

### k8s_fullapex_deploy.yaml
This creates a Persistant Volume Claim on a Filesystem that should already be present
It creates a deployment and so a pod as instantiation of the image
It creates a CLusterIP service on port 1521 (database) and 8080 (ords)


### Developed on:
*WSL2*
*Docker-Desktop*
