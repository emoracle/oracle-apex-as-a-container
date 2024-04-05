# Oracle Database Container Deployment Script

This script automates the deployment and configuration of an Oracle Database container, including the setup of Oracle Application Express (APEX) and Oracle REST Data Services (ORDS), ensuring a quick start for development or testing purposes.

## Prerequisites

- **Docker**: The script requires Docker to be installed and running on your machine.
- **Environment Variables**: Before running the script, ensure the following environment variables are set:
  - `REGISTRY_USER`: Your Oracle Container Registry username.
  - `REGISTRY_PWD`: Your Oracle Container Registry password.
  - `SYS_PWD`: The SYS user password for the Oracle database.
  - `CONTAINER_NAME`: The name you wish to assign to your Oracle database container.
  - `ADMIN_PWD`: The admin user password for Oracle APEX.

## Features

- **Oracle Database Container**: Pulls and runs the latest Oracle Database image from the Oracle Container Registry.
- **Oracle APEX**: Downloads and installs the latest version of Oracle APEX into the database.
- **ORDS**: Sets up and configures Oracle REST Data Services for use with the Oracle Database and APEX.
- **Health Check**: Ensures the database is fully operational before proceeding with APEX and ORDS setup.
- **Environment Validation**: Checks for necessary environment variables and Docker daemon before proceeding.
- **Initialization Script**: Supports executing custom SQL scripts during the setup for application-specific database objects.
- **Security**: Includes steps for changing the APEX admin password and auto-configuration for ORDS.

## Usage

1. **Set Environment Variables**: Export the necessary environment variables (`REGISTRY_USER`, `REGISTRY_PWD`, `SYS_PWD`, `CONTAINER_NAME`, `ADMIN_PWD`) in your terminal session.

2. **Run the Script**: Execute the script in your terminal. Ensure you have sufficient permissions to invoke Docker commands.

3. **Access APEX**: Once the script completes, Oracle APEX can be accessed at `http://localhost:8080/ords`. Log in using the APEX admin credentials you specified.

4. **Database Connection**: Connect to your Oracle database using the standard connection details provided by the script output, including the `SYS_PWD` password for SYS user access.

## Troubleshooting

- Ensure Docker is running before executing the script.
- Verify all required environment variables are correctly set.
- Check Docker and script logs for any error messages if the container fails to start or APEX/ORDS setup does not complete.

## Contributing

Your contributions are welcome. Please feel free to submit pull requests or report any issues you encounter.
