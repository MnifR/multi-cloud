# Configuration

Share the specific runner `k8s-dev-runner` created in `devops` repo with this project.
You need `Maintainer` permission.

```shell
GCP_PROJECT_ID=<GCP_PROJECT_ID>
sed -i "s/<GCP_PROJECT_ID>/${GCP_PROJECT_ID}" base/demo-deployment.yaml
```