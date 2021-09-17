One-shot Kubernetes deployment of SODALITE
==========================================

This deploys the sodalite stack into the ``sodalite-services``
namespace. It is a one-shot -- changes require destrying the whole 
namespace and redeploying.

Deploying
---------

``./load_into_k8s.sh``

If you use an alternative but command-line compatible utility to manage
kubernetes (eg: microk8s), you can set this to use it via the KUBECTL
environment variable.  For example:

``KUBECTL="microk8s kubectl" ./load_into_k8s.sh``

Undeploying
-----------

``kubectl delete -f namespace-sodalite-services.yaml``

Cleaning up
-----------

To delete all generated files:

``rm $(cat .gitignore)``

This is likely not the safest and depends on everyone keeping ``.gitignore``
up to date. May be replaced later.