# SODALITE stack local machine docker blueprint
Implementation of the blueprint and integration tests for the SODALITE platform stack on local machine using docker.

This repository contains the TOSCA/Ansible SODALITE stack deployment blueprints which can be deployed by SODALITE orchestrator [xOpera](https://github.com/xlab-si/xopera-opera). The blueprint installs SODALITE stack components on local machine using docker to setup the components (not reccomended for real development). 

NOTE: SODALITE currently uses the version [xOpera version 0.6.2](https://pypi.org/project/opera/0.6.2/) since xOpera is beeing developed to support [OASIS TOSCA Simple Profile in YAML version 1.3](https://www.oasis-open.org/news/announcements/tosca-simple-profile-in-yaml-v1-3-oasis-standard-published).

NOTE: `local_setup.yaml` blueprint creates an Ubuntu VM that installs all prerequisites for local deployment (pip, xOpera) and can be used to test SODALITE platform stack on local machine.
