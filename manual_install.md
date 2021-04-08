# Manual installation of SODALITE iac-platform-stack

Prerequisites for SODALITE stack deployment could also be set manually, following these steps:
1.  ## Install xOpera 
    Install xOpera and required modules as described here: [xOpera](https://github.com/xlab-si/xopera-opera)    
        *NOTE: Use `--system-site-packages` flag when setting up Python virtual environment in order to avoid this [issue](https://github.com/ansible/ansible/issues/14468)*
        
2.  ## Install required Ansible roles
    Ansible roles are listed in the [requirements.yml](requirements.yml) Roles installation can be performed using this command:
    ```shell script
    ansible-galaxy install -r docker-local/requirements.yml -f
    ```
   
3.  ## Clone modules 
    Clone TOSCA node types and Ansible playbooks required for deployment from [iac-modules](https://github.com/SODALITE-EU/iac-modules) into blueprint folders (`./docker-local` or `./openstack`)
    ```shell script
    # $DEPLOY_DIR could be set to either docker-local or openstack
    export DEPLOY_DIR=docker-local
    export IAC_MODULES_VERSION=3.4.1
    git clone -b "$IAC_MODULES_VERSION" https://github.com/SODALITE-EU/iac-modules.git $DEPLOY_DIR/modules
    ```  
 
4.  ## Generate TLS certificate and key files
    TLS certificates are required for Reverse Proxies an Docker Registry.  
    SODALITE stack requires a private Docker registry to store Docker images. For demonstration purposes a Docker registry container is deployed as a part of SODALITE stack blueprint. In order to make registry accessible to external hosts, is must be secured using TLS certificate. [Docker private registry configuration](https://docs.docker.com/registry/deploying/) TLS certificate and key required for that are not provided in the repository for security reasons and can be generated using following commands:
    ```shell script
    # $DEPLOY_DIR could be set to either docker-local or openstack
    export DEPLOY_DIR=docker-local
    openssl genrsa -out $DEPLOY_DIR/modules/docker/artifacts/ca.key 4096
    openssl req -new -x509 -key $DEPLOY_DIR/modules/docker/artifacts/ca.key -out $DEPLOY_DIR/modules/docker/artifacts/ca.crt
    cp $DEPLOY_DIR/modules/docker/artifacts/ca.key $DEPLOY_DIR/modules/misc/tls/artifacts/ca.key
    cp $DEPLOY_DIR/modules/docker/artifacts/ca.crt $DEPLOY_DIR/modules/misc/tls/artifacts/ca.crt
    ```

5.  ## Set up inputs for deployment
    Input YAML files provided  in the repository are not supposed to be used as is, but rather serve as a template to be populated with actual values. In order for SODALITE stack deployment to proceed some of inputs must be defined. Namely 
    `docker-registry-cert-email-address` used for Docker self signed certificate and Gitlab auth token `XOPERA_GIT_AUTH_TOKEN` that grants access to git repository for TOSCA blueprints. To provide inputs manually edit `input.yaml.tmpl` file and save it as `input.yaml`.

    Openstack deployment of SODALITE stack requires a VM to be instantiated therefore these parameters have to be defined: SSH key, image, flavor and network names plus a comma separated list of security groups.
    ```yaml
    ssh-key-name: 
    image-name:
    username: 
    flavor-name:
    openstack-network-name: 
    security-groups:     
    ```
    *NOTE: `security-groups` input must include `sodalite-uc`security group, e.g. `default,remote_access,sodalite-uc`*
    
6.  ## Export OPERA_SSH_USER (OpenStack only)
    By default, xOpera tries to connect to VM with default user centos:
    ```shell script
    ssh centos@[vm_ip]
    ```
    If deploying to image with default user other then centos (e.g. ubuntu), OPERA_SSH_USER must be exported:
    ```shell script
    # example for Ubuntu 20.04 cloud image
    export OPERA_SSH_USER=ubuntu
    ```
    
7.  ## Run blueprint deployment
    Go to the folder containing `service.yaml` TOSCA blueprint file (`./docker-local` or `./openstack`) and run the following command:
    ```shell script
    opera deploy -i input.yaml service.yaml
    ```
