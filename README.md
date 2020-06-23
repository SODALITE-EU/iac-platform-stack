# iac-platform-stack
Implementation of the blueprint and integration tests for the SODALITE platform stack

SODALITE uses IaC, namely the well known Topology and Orchestration Specification for Cloud Applications [TOSCA](https://www.oasis-open.org/committees/tc_home.php?wg_abbrev=tosca) OASIS standard for modelling the infrastructure and application deployment. The TOSCA lifecycle operation interfaces are implemented in [Ansible](https://www.ansible.com/) playbooks and roles. 
This repository contains the TOSCA/Ansible SODALITE stack deployment blueprints which can be deployed by SODALITE orchestrator [xOpera](https://github.com/xlab-si/xopera-opera). 

This repository contains two deployment blueprints for the SODALITE platform supporting [openstack](https://www.openstack.org/) private cloud deployment and local machine docker setup (not reccomended for real development). 

NOTE: SODALITE currently uses the version [xOpera version 0.5.7](https://pypi.org/project/opera/0.5.7/) since xOpera is beeing developed to support [OASIS TOSCA Simple Profile in YAML version 1.3](https://www.oasis-open.org/news/announcements/tosca-simple-profile-in-yaml-v1-3-oasis-standard-published).