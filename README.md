# Oracle Database Container Deployment Script 

This script automates the deployment and configuration of an Oracle Database container, including the setup of Oracle Application Express (APEX) and Oracle REST Data Services (ORDS), ensuring a quick start for development or testing purposes.

## Prerequisites

- **Docker**: The script requires Docker to be installed and running on your machine.
- **Environment Variables**: Before running the script, ensure the following environment variables are set:
  - `REGISTRY_USER`: Your Oracle Container Registry username.
  - `REGISTRY_TOKEN`: Your Oracle Container Registry authentication token.
  - `SYS_PWD`: The SYS user password for the Oracle database.
  - `CONTAINER_NAME`: The name you wish to assign to your Oracle database container.
  - `ADMIN_PWD`: The admin user password for Oracle APEX.
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

1. **Configure the Local Wrapper**: The local `build/startContainer.sh` contains fixed exports for credentials, the container name and the APEX/ORDS installation flags. Check these settings before running it. The wrapper does not prompt for credentials and its exports override existing environment values. `REGISTRY_TOKEN` is used for registry authentication; the legacy `REGISTRY_PWD` export is not used for login. Credentials are stored in plaintext in this local file: restrict access and do not share or commit it. `/build` is excluded from Git. As an alternative, run `maak_container_free.sh` directly with the required environment variables supplied securely.

2. **Run the Script**: From the project root, run the following commands. The wrapper uses relative paths, so it must run from `build`. Ensure Docker is running and you have permission to invoke Docker commands.

   ```bash
   cd build
   bash startContainer.sh
   ```

3. **Access APEX**: When APEX and ORDS are enabled and installation completes, Oracle APEX can be accessed at `http://localhost:8080/ords/apex`. Log in using the APEX admin credentials you specified.

4. **Database Connection and Logs**: Use the connection command shown by the installer and enter `SYS_PWD` when SQL*Plus prompts. Passwords are not printed. The installer redacts literal occurrences of configured secret values in its output, including upstream error messages. The wrapper removes the previous `build/install.log` and records new output there using `tee`. It does not enforce mode `600`; permissions depend on your current umask. To restrict access to newly created logs, run `umask 077` before starting the wrapper.

Credentials previously stored in scripts or installation logs should be rotated through their respective registry/database administrators. Updating these scripts does not rotate existing credentials or sanitize historical copies and logs. Demo-account passwords and network settings are separate configuration concerns.

## Troubleshooting

- Ensure Docker is running before executing the script.
- Verify all required environment variables are correctly set.
- Check Docker and script logs for any error messages if the container fails to start or APEX/ORDS setup does not complete.
- /etc/yum/vars/ociregion file is deleted from yum an recreated empty to force dnf/yum to go to yum.oracle.com

## Contributing

Your contributions are welcome. Please feel free to submit pull requests or report any issues you encounter.
