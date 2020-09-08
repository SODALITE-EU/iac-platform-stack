pipeline {
    agent { label 'docker-slave' }
    environment {
       // OPENSTACK SETTINGS
       ssh_key_name = "jenkins-opera"
       image_name = "centos7"
       network_name = "orchestrator-network"
       security_groups = "default,sodalite-remote-access,sodalite-rest,sodalite-uc"
       flavor_name = "m1.medium"
       // DOCKER SETTINGS
       docker_network = "sodalite"
       dockerhub_user = " "
       dockerhub_pass = " "
       docker_registry_ip = credentials('jenkins-docker-registry-ip')
       docker_registry_cert_country_name = "SI"
       docker_registry_cert_organization_name = "XLAB"
       docker_public_registry_url = "registry.hub.docker.com"
       docker_registry_cert_email_address = "dragan.radolovic@xlab.si"
       // POSTGRES SETTINGS
       postgres_address = "xopera-postgres"
       postgres_user = credentials('postgres-user')
       postgres_password = credentials('postgres-password')
       postgres_db = "postgres"
       // XOPERA SETTINGS
       verbose_mode = "debug"
       // GIT SETTINGS
       git_type = "gitlab"
       git_url = "https://gitlab.com"
       git_auth_token = credentials('git-auth-token')
       // OPENSTACK DEPLOYMENT FALLBACK SETTINGS
       OS_PROJECT_DOMAIN_NAME = "Default"
       OS_USER_DOMAIN_NAME = "Default"
       OS_PROJECT_NAME = "orchestrator"
       OS_TENANT_NAME = "orchestrator"
       OS_USERNAME = credentials('os-username')
       OS_PASSWORD = credentials('os-password')
       OS_AUTH_URL = credentials('os-auth-url')
       OS_INTERFACE = "public"
       OS_IDENTITY_API_VERSION = "3"
       OS_REGION_NAME = "RegionOne"
       OS_AUTH_PLUGIN = "password"

       // DOCKER CERTIFICATES
       ca_crt_file = credentials('xopera-ca-crt')
       ca_key_file = credentials('xopera-ca-key')
   }
    stages {
        stage ('Pull repo code from github') {
            steps {
                checkout scm
            }
        }
        stage('Install dependencies') {
            when { tag "*" }
            steps {
                sh "virtualenv venv"
                sh ". venv/bin/activate; python -m pip install -U 'opera[openstack]==0.5.7'"
                sh ". venv/bin/activate; python -m pip install docker"
                sh ". venv/bin/activate; python -m pip install python-PROJECTclient"
                sh ". venv/bin/activate; ansible-galaxy install -r tests/requirements.yml"
            }
        }
        stage('Install required certificates') {
            when { tag "*" }
            steps {
                sh "cp ${ca_crt_file} /modules/docker/artifacts/"
                sh "cp ${ca_key_file} /modules/docker/artifacts/"
                sh "cat ${xOpera_ssh_key_file} >> ~/.ssh/authorized_keys"
            }
        }
        stage('Copy modules to /openstack/ and /tests/') {
            when { tag "*" }
            steps {
                sh "cp -R /modules /openstack/"
                sh "cp -R /modules /tests/"
            }
        }
        stage('Deploy Sodalite stack to OpenStack') {
            when { tag "*" }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'xOpera_ssh_key', keyFileVariable: 'xOpera_ssh_key_file', usernameVariable: 'xOpera_ssh_username')]) {
                    // BUILD THE INPUTS FILE
                    sh """\
                    echo "# OPENSTACK SETTINGS
                    ssh-key-name: ${ssh_key_name}
                    image-name: ${image_name}
                    openstack-network-name: ${network_name}
                    security-groups: ${security_groups}
                    flavor-name: ${flavor_name}
                    # DOCKER SETTINGS
                    docker-network: ${docker_network}
                    dockerhub-user: ${dockerhub_user}
                    dockerhub-pass: ${dockerhub_pass}
                    docker-public-registry-url: ${docker_public_registry_url}
                    docker-private-registry-url: ${docker_registry_ip}
                    docker-registry-cert-country-name: ${docker_registry_cert_country_name}
                    docker-registry-cert-organization-name: ${docker_registry_cert_organization_name}
                    docker-registry-cert-email-address: ${docker_registry_cert_email_address}
                    # POSTGRES SETTINGS
                    postgres_env:
                      postgres_user: ${postgres_user}
                      postgres_password: ${postgres_password}
                      postgres_db: ${postgres_db}
                    # XOPERA SETTINGS
                    xopera_env:
                      XOPERA_VERBOSE_MODE: ${verbose_mode}
                      # XOPERA GIT SETTINGS
                      XOPERA_GIT_TYPE: ${git_type}
                      XOPERA_GIT_URL: https://gitlab.com
                      XOPERA_GIT_AUTH_TOKEN: ${git_auth_token}
                      # XOPERA POSTGRES CONNECTION
                      XOPERA_DATABASE_IP: ${postgres_address}
                      XOPERA_DATABASE_NAME: ${postgres_db}
                      XOPERA_DATABASE_USER: ${postgres_user}
                      XOPERA_DATABASE_PASSWORD: ${postgres_password}
                      # OPENSTACK DEPLOYMENT FALLBACK SETTINGS
                      OS_PROJECT_DOMAIN_NAME: ${OS_PROJECT_DOMAIN_NAME}
                      OS_USER_DOMAIN_NAME: ${OS_USER_DOMAIN_NAME}
                      OS_PROJECT_NAME: ${OS_PROJECT_NAME}
                      OS_TENANT_NAME: ${OS_TENANT_NAME}
                      OS_USERNAME: ${OS_USERNAME}
                      OS_PASSWORD: ${OS_PASSWORD}
                      OS_AUTH_URL: ${OS_AUTH_URL}
                      OS_INTERFACE: ${OS_INTERFACE}
                      OS_IDENTITY_API_VERSION: "${OS_IDENTITY_API_VERSION}"
                      OS_REGION_NAME: ${OS_REGION_NAME}
                      OS_AUTH_PLUGIN: ${OS_AUTH_PLUGIN}
                    # IMAGE BUILDER SETTINGS
                    image_builder_env:
                      REGISTRY_IP: ${docker_registry_ip}" > openstack/input.yaml
                    """.stripIndent()
                    // PRINT THE INPUT YAML FILE
                    sh 'cat openstack/input.yaml'
                    // DEPLOY XOPERA REST API
                    sh ". venv/bin/activate; cd openstack; rm -r -f .opera; opera deploy service.yaml -i input.yaml"
                }
            }
        }
        stage('Extract IP from deployment outputs') {
            when { tag "*" }
            steps {
                def sodalite_output = sh (
                    script: '. venv/bin/activate; cd openstack; opera outputs',
                    returnStdout: true
                ).trim()
                def sodalite_output_yaml = readYaml text: sodalite_output
                environment {
                    SODALITE_SERVICE_IP = sodalite_output_yaml["public_ip_address"]["value"];
                }
            }
        }
        stage('Get SSH key from the deployment') {
            when { tag "*" }
            steps {
                def get_ssh_key_response = sh (
                    script: "curl -X GET \"https://${SODALITE_SERVICE_IP}:5001/ssh/keys/public\" -H  \"accept: application/json\"",
                    returnStdout: true
                ).trim()
                def get_ssh_key_response_json = readJSON text: get_ssh_key_response
                environment {
                    SODALITE_SSH_KEY_NAME = get_ssh_key_response_json["key_pair_name"];
                    SODALITE_SSH_KEY = get_ssh_key_response_json["public_key"];
                }
            }
        }
        stage('Upload SSH key to OpenStack') {
            when { tag "*" }
            steps {
                sh "echo \"${SODALITE_SSH_KEY}\" > ${SODALITE_SSH_KEY_NAME}.key"
                sh "openstack keypair create ${SODALITE_SERVICE_IP} --public ${SODALITE_SSH_KEY_NAME}.key"
            }
        }
        stage('Prepare input file for test deployment') {
            when { tag "*" }
            steps {
                // BUILD THE INPUTS FILE FOR TESTS
                sh """\
                echo "
                ssh-key-name: ${SODALITE_SSH_KEY_NAME}
                image-name: "centos-7"
                openstack-network-name: ${network_name}
                security-groups: default,remote_access,snow
                flavor-name: m1.medium
                docker-network: snow
                docker-registry-url: ${docker_registry_ip}
                docker-registry-cert-country-name: ${docker_registry_cert_country_name}
                docker-registry-cert-organization-name: ${docker_registry_cert_organization_name}
                docker-registry-cert-email-address: ${docker_registry_cert_email_address}
                mysql-db-pass: somepassword
                mysql-env:
                  MYSQL_DATABASE: wc_crawler_db
                  MYSQL_ROOT_PASSWORD: somepassword" > tests/artifacts/input.yaml
                """.stripIndent()
                // PRINT THE INPUT YAML FILE
                sh 'cat tests/artifacts/input.yaml'
            }
        }
        stage('Prepare input file for tests') {
            when { tag "*" }
            steps {
                // BUILD THE INPUTS FILE FOR TESTS
                sh """\
                echo "
                blueprint-builder-address: http://${SODALITE_SERVICE_IP}:8081/
                xopera-rest-address: https://${SODALITE_SERVICE_IP}:5001/
                image-builder-address: https://${SODALITE_SERVICE_IP}:5002/
                sematic-reasoner-call: http://160.40.52.200:8084/reasoner-api/v0.6/aadm?aadmIRI=https://www.sodalite.eu/ontologies/workspace/1/vbeit9auui3d3j0tdekbljfndl/AADM_92aj0uo7t6l6u8mv5tmh99pjnb
                " > tests/tests/input.yaml
                """.stripIndent()
                // PRINT THE INPUT YAML FILE
                sh 'cat tests/tests/input.yaml'
            }
        }
        stage('Deploy tests to OpenStack') {
            when { tag "*" }
            steps {
                // DEPLOY TESTS
                sh ". venv/bin/activate; cd tests; rm -r -f .opera; opera deploy full_test.yaml -i tests/input.yaml"
            }
        }
        stage('Verify test status') {
            when { tag "*" }
            steps {
                def test_output = sh (
                    script: '. venv/bin/activate; cd tests; opera outputs',
                    returnStdout: true
                ).trim()
                def test_output_yaml = readYaml text: sodalite_output

                def critical_nodes = [  "sr_download_node",
                                        "bp_builder_connect_node",
                                        "bp_builder_upload_test",
                                        "xopera_root_connect_node",
                                        "xopera_public_key_node",
                                        "xopera_deploy_node",
                                        "xopera_deployment_status_node",
                                        "xopera_undeploy_node",
                                        "xopera_delete_node"                ]

                def warning_nodes = [   "xopera_undeployment_status_node"   ]

                for (int i = 0; i < critical_nodes.size(); i++) {
                    println(critical_nodes[i] + " test(" + test_output_yaml[critical_nodes[i]]["description"] + "): " + test_output_yaml[critical_nodes[i]]["value"])
                    if(!test_output_yaml[critical_nodes[i]]["value"].toBoolean())
                        throw new Exception("Node " + critical_nodes[i] + " failed!")
                }

                for (int i = 0; i < warning_nodes.size(); i++) {
                    println(warning_nodes[i] + " test(" + test_output_yaml[warning_nodes[i]]["description"] + "): " + test_output_yaml[warning_nodes[i]]["value"])
                    if(!test_output_yaml[warning_nodes[i]]["value"].toBoolean())
                        println("Node " + warning_nodes[i] + " failed, but is ignored in the result of this test!")
                }
            }
        }
    }
}