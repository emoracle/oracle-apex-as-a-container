# Oracle Database Container Deployment Script 

This script automates the deployment and configuration of an Oracle Database container, including the setup of Oracle Application Express (APEX) and Oracle REST Data Services (ORDS), ensuring a quick start for development or testing purposes.

## Prerequisites

- **Docker**: The script requires Docker to be installed and running on your machine.
- **Environment Variables**: Configure the following variables in the root `.env` file or the calling environment:
  - `REGISTRY`: Destination registry and namespace for image publishing and cleanup, loaded from `.env` by each script.
  - `REGISTRY_USER`: Your Oracle Container Registry username.
  - `REGISTRY_TOKEN`: Your Oracle Container Registry authentication token.
  - `SYS_PWD`: The SYS user password for the Oracle database.
  - `CONTAINER_NAME`: The name you wish to assign to your Oracle database container.
  - `ADMIN_PWD`: The admin user password for Oracle APEX (required when `INSTALL_APEX=TRUE`).
  - `INSTALL_APEX`: APEX must be installed (TRUE) or not (FALSE)
  - `INSTALL_ORDS`: ORDS must be installed (TRUE) or not (FALSE). APEX installation is a prerequisite.

## Features

- **Oracle Database Container**: Pulls and runs the latest Oracle Database image from the Oracle Container Registry.
- **Oracle APEX**: Downloads and installs the latest version of Oracle APEX into the database.
- **ORDS**: Sets up and configures Oracle REST Data Services for use with the Oracle Database and APEX.
- **Health Check**: Ensures the database is fully operational before proceeding with APEX and ORDS setup.
- **Environment Validation**: Checks for necessary environment variables and Docker daemon before proceeding.
- **Initialization Script**: Supports executing custom SQL scripts during the setup for application-specific database objects.
- **Security**: Includes steps for changing the APEX admin password and auto-configuration for ORDS.

## Usage

1. **Configure `.env`**: Copy the committed template with `cp .env.sample .env`, run `chmod 600 .env`, and replace all dummy values with your own settings. Shared settings and credentials live in `.env` at the project root, beside `maak_container_free`. This file is excluded from Git. Use Bash assignments such as `REGISTRY="fra.ocir.io/juva2oca/"` and `CONTAINER_NAME="thuistest"`, with the remaining variables listed above. Quote values containing special characters. Keep credentials private (`chmod 600 .env`). Values in `.env` override existing environment values; without the file, scripts use the calling environment. `REGISTRY_PWD` is a legacy setting and is not used by the database installer for login.

2. **Run the Script**: Ensure Docker is running, then run from the project root:

   ```bash
   ./start_container.sh
   ```

   `start_container.sh` is the executable entrypoint. It invokes the non-executable `maak_container_free` installer through Bash.

   The installer, wrapper, image publisher, and cleanup helper automatically load the root `.env`, regardless of the current working directory. Image publishing also uses its shared `CONTAINER_NAME`.

3. **Access APEX**: When APEX and ORDS are enabled and installation completes, Oracle APEX can be accessed at `http://localhost:8080/ords/apex`. Log in using the APEX admin credentials you specified.

   New containers bind ports 1521, 8080 and 8443 to `127.0.0.1` on the Docker host only. Existing containers with non-loopback bindings, automatic port publishing or host/shared-container networking are rejected before reuse or startup. Docker cannot change these bindings with a restart: safeguard the database data before recreating such a container. Remote access requires a separately secured setup with HTTPS; the HTTP endpoint is intended for local use.

4. **Database Connection and Logs**: Use the connection command shown by the installer and enter `SYS_PWD` when SQL*Plus prompts. Passwords are not printed. The installer redacts literal occurrences of configured secret values in its output, including upstream error messages. The wrapper removes the previous `build/install.log` and records new output there using `tee`. It does not enforce mode `600`; permissions depend on your current umask. To restrict access to newly created logs, run `umask 077` before starting the wrapper.

Credentials previously stored in scripts or installation logs should be rotated through their respective registry/database administrators. Updating these scripts does not rotate existing credentials or sanitize historical copies and logs. Demo-account passwords and network settings are separate configuration concerns.

The local `build/maak_k8s_image.sh` and `build/cleanup_docker.sh` scripts use `REGISTRY` from `.env` for destination image references. Both accept the prefix with or without a trailing slash. The Oracle database source image continues to use `container-registry.oracle.com`.

## Troubleshooting

- Ensure Docker is running before executing the script.
- Verify all required environment variables are correctly set.
- Check Docker and script logs for any error messages if the container fails to start or APEX/ORDS setup does not complete.
- /etc/yum/vars/ociregion file is deleted from yum an recreated empty to force dnf/yum to go to yum.oracle.com

## Contributing

Your contributions are welcome. Please feel free to submit pull requests or report any issues you encounter.
