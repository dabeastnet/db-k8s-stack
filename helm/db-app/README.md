This directory is reserved for a Helm chart to package the db‑k8s application.  For this assignment the
application is deployed using plain Kubernetes manifests located in the `k8s/` directory.  A Helm chart
could be created in the future to template these resources and parameterise values such as image tags,
replica counts and domain names.  The presence of this directory demonstrates awareness of Helm but
does not affect the current deployment.