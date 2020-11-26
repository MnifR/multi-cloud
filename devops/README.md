# Google Cloud

Export global variables

```shell
export GCP_PROJECT_ID=<GCP_PROJECT_ID>
export SW_PROJECT_NAME=<SW_PROJECT_NAME>
export GIT_REPOSITORY_URL=<MY_REPO>/demo-env.git

export GCP_REGION_DEFAULT=europe-west1
export GCP_GKE_CLUSTER_ZONE=europe-west1-b

export GCP_KUBE_CONTEXT_NAME="gke_${GCP_PROJECT_ID}_${GCP_GKE_CLUSTER_ZONE}_gke-cluster-devops"

export PUBLIC_DNS_NAME=demo-cre.stack-labs.com
export PUBLIC_DNS_ZONE_NAME=demo-cre

export TERRAFORM_BUCKET_NAME=bucket-${GCP_PROJECT_ID}-sw-gcp-terraform-backend
```

Create gcs bucket for terraform states

```shell
gcloud config set project ${GCP_PROJECT_ID}
gsutil mb -c standard -l ${GCP_REGION_DEFAULT} gs://${TERRAFORM_BUCKET_NAME}
gsutil versioning set on gs://${TERRAFORM_BUCKET_NAME}
```

Initialize google cloud devops infrastructure. The states will be saved in GCP.

```shell
cd infra/plan
terraform init \
  -backend-config="bucket=${TERRAFORM_BUCKET_NAME}" \
  -backend-config="prefix=googlecloud/terraform/state"
```

Complete `infra/plan/terraform.tfvars` and run 

```shell
sed -i "s/<LOCAL_IP_RANGES>/$(curl -s http://checkip.amazonaws.com/)\/32/g;s/<PUBLIC_DNS_NAME>/${PUBLIC_DNS_NAME}/g;s/<GCP_PROJECT_ID>/${GCP_PROJECT_ID}/g;s/<GCP_REGION>/${GCP_REGION_DEFAULT}/g;s/<GCP_GKE_CLUSTER_ZONE>/${GCP_GKE_CLUSTER_ZONE}/g" terraform.tfvars
terraform apply
```

This will create the following resources:

- Enables the required services on that project
- Creates a bucket for storage
- Creates a KMS key for encryption
- Creates a service account with the most restrictive permissions to those resources
- Creates a GKE cluster with the configured service account attached
- Creates a public IP
- Generates a self-signed certificate authority (CA)
- Generates a certificate signed by that CA
- Configures Terraform to talk to Kubernetes
- Creates a Kubernetes secret with the TLS file contents
- Configures your local system to talk to the GKE cluster by getting the cluster credentials and kubernetes context
- Submits the StatefulSet and Service to the Kubernetes API

Access the GKE Cluster using

```shell
gcloud container clusters get-credentials gke-cluster-devops --zone ${GCP_GKE_CLUSTER_ZONE} --project ${GCP_PROJECT_ID}
```

# Vault

Install [vault](https://learn.hashicorp.com/tutorials/vault/getting-started-install) 

Vault reads these environment variables for communication. Set Vault's address, the CA to use for validation, and the initial root token.

```shell
# Make sure you are in the terraform/ directory
# cd infra/plan

export VAULT_ADDR="https://$(terraform output address)"
export VAULT_TOKEN="$(eval `terraform output root_token_decrypt_command`)"
export VAULT_CAPATH="$(cd ../ && pwd)/tls/ca.pem"
```

Save scaleway credentials:

```shell
vault secrets enable -path=scaleway/project/${SW_PROJECT_NAME} -version=2 kv
vault kv put scaleway/project/${SW_PROJECT_NAME}/credentials/access key="<SCW_ACCESS_KEY>"
vault kv put scaleway/project/${SW_PROJECT_NAME}/credentials/secret key="<SCW_SECRET_KEY>"
vault kv put scaleway/project/${SW_PROJECT_NAME}/config id="<SW_PROJECT_ID>"
```

Create google service account to authorize GitLab to read from terraform state

```shell
gcloud iam service-accounts create gsa-dev-deployer

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --role roles/container.developer \
  --member "serviceAccount:gsa-dev-deployer@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --role roles/secretmanager.secretAccessor \
  --member "serviceAccount:gsa-dev-deployer@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --role roles/cloudbuild.builds.builder \
  --member "serviceAccount:gsa-dev-deployer@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --role roles/iam.serviceAccountAdmin \
  --member "serviceAccount:gsa-dev-deployer@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
```

```shell
kubectl create namespace sw-dev
```

To bind a gsa to a ksa

```shell
kubectl create serviceaccount -n sw-dev ksa-sw-dev-deployer

gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${GCP_PROJECT_ID}.svc.id.goog[sw-dev/ksa-sw-dev-deployer]" \
  gsa-dev-deployer@${GCP_PROJECT_ID}.iam.gserviceaccount.com

kubectl annotate serviceaccount \
  -n sw-dev \
  ksa-sw-dev-deployer \
  iam.gke.io/gcp-service-account=gsa-dev-deployer@${GCP_PROJECT_ID}.iam.gserviceaccount.com
```

Create the policy named policy-sw-dev-deployer with the contents from stdin

```shell
vault policy write policy-sw-dev-deployer - <<EOF
# Read-only permissions

path "scaleway/project/${SW_PROJECT_NAME}/*" {
  capabilities = [ "read" ]
}

EOF
```

Create a token and add the policy-sw-dev-deployer policy.

```shell
GITLAB_RUNNER_VAULT_TOKEN=$(vault token create -policy=policy-sw-dev-deployer | grep "token" | awk 'NR==1{print $2}')
```

To get a temporary access token, configure auth methods to automatically assign a set of policies to tokens

```shell
vault auth enable approle

vault write auth/approle/role/sw-dev-deployer \
    secret_id_ttl=10m \
    token_num_uses=10 \
    token_ttl=20m \
    token_max_ttl=30m \
    secret_id_num_uses=40 \
    token_policies=policy-sw-dev-deployer

ROLE_ID=$(vault read -field=role_id auth/approle/role/sw-dev-deployer/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/sw-dev-deployer/secret-id)
GITLAB_RUNNER_VAULT_TOKEN=$(vault write auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID" | grep "token" | awk 'NR==1{print $2}')
```

If you have a cloud DNS available, you can create an alias record

```shell
gcloud dns record-sets transaction start --zone=$PUBLIC_DNS_ZONE_NAME
gcloud dns record-sets transaction add "$(gcloud compute addresses list --filter=name=vault-lb --format="value(ADDRESS)")" --name=vault.$PUBLIC_DNS_NAME. --ttl=300  --type=A --zone=$PUBLIC_DNS_ZONE_NAME
gcloud dns record-sets transaction execute --zone=$PUBLIC_DNS_ZONE_NAME
VAULT_ADDR="https://vault.${PUBLIC_DNS_NAME}"
```

Save vault token in secret manager

```shell
gcloud beta secrets create vault-token --locations $GCP_REGION_DEFAULT --replication-policy user-managed
echo -n "${GITLAB_RUNNER_VAULT_TOKEN}" | gcloud beta secrets versions add vault-token --data-file=-
```

# GitLab CI

Add Gitlab SSH Key to allow the runner to push on git repositories

```shell
gcloud beta secrets create gitlab-ssh-key --locations $GCP_REGION_DEFAULT --replication-policy user-managed
cd ~/.ssh
ssh-keygen -t rsa -b 4096
gcloud beta secrets versions add gitlab-ssh-key --data-file=./id_rsa
```

```shell
GITLAB_SSH_KEY=$(gcloud secrets versions access latest --secret=gitlab-ssh-key)
```

Create docker image with vault, argocd, terraform, gcloud sdk, sw cli. It will be used by the gitlab runner

```shell
cd docker
gcloud builds submit --config cloudbuild.yaml --substitutions \
_VAULT_CA="$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ../infra/tls/ca.pem)",_VERSION="latest",_GITLAB_SSH_KEY="$GITLAB_SSH_KEY",_PROJECT_ID="$GCP_PROJECT_ID"
```

Install Helm 3

```shell
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

Add kubernetes role to the service account that will be used by Gitlab CI

```shell
kubectl apply -f gitlab/dev/rbac-gitlab-demo-dev.yml
```

Add gitlab package

```shell
helm repo add gitlab https://charts.gitlab.io
```

Save the runner registration token in a secret

```shell
kubectl create secret generic secret-sw-devops-gitlab-runner-tokens --from-literal=runner-token='' --from-literal=runner-registration-token='<DEMO_INFRA_REPO_RUNNER_TOKEN>' -n sw-dev
```

Clone the repository and install the Gitlab Runner

```shell
helm install -n sw-dev sw-dev -f gitlab/dev/values.yaml gitlab/gitlab-runner
```

Test if the gitlab runner authorization

```shell
kubectl run -it \
  --image eu.gcr.io/${GCP_PROJECT_ID}/tools \
  --serviceaccount ksa-sw-dev-deployer \
  --namespace sw-dev \
  gitlab-runner-auth-test
```

Inside the pod container, run `gcloud auth list`. You can delete the pod afterwards `kubectl delete pod gitlab-runner-auth-test -n sw-dev`.

# Gitlab Projects

- Add protected tags `v*` on both repositories `-app` and `-env`. Go to `Settings > Repository > Protected Tags`.
- Enable gitlab runners on `-infra`, `-env` and `-app`. Go to `Settings > CI / CD > Runners > Specific Runners > Enable for this project`.
- Lock gitlab runners for current projets (icon "edit" of the activated runner).

# ArgoCD

Argo CD is a declarative, GitOps continuous delivery tool for Kubernetes.

Install Argo CD

```shell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user="$(gcloud config get-value account)"
```

Access the Argo CD API Server

```shell
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

Download Argo CD CLI

```shell
ARGOCD_VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

Configure app-demo-dev application

```shell
cd k8s
export GITLAB_USERNAME_SECRET=<GITLAB_USERNAME_SECRET>
export GITLAB_CI_PUSH_TOKEN=<GITLAB_CI_PUSH_TOKEN>
kubectl create secret generic demo -n argocd \
--from-literal=username=$GITLAB_USERNAME_SECRET \
--from-literal=password=$GITLAB_CI_PUSH_TOKEN
```

If you have a cloud DNS available, we can create an ingress for ArgoCD and attach an external static IP and a managed SSL certificate

```shell
gcloud compute addresses create argocd --global
gcloud dns record-sets transaction start --zone=$PUBLIC_DNS_ZONE_NAME
gcloud dns record-sets transaction add $(gcloud compute addresses list --filter=name=argocd --format="value(ADDRESS)") --name=argocd.$PUBLIC_DNS_NAME. --ttl=300  --type=A --zone=$PUBLIC_DNS_ZONE_NAME
gcloud dns record-sets transaction execute --zone=$PUBLIC_DNS_ZONE_NAME
```

```shell
gcloud compute firewall-rules create fw-allow-health-checks \
    --network=vpc \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=35.191.0.0/16,130.211.0.0/22 \
    --rules=tcp
```

Enable ingress argocd

```shell
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
kubectl annotate svc argocd-server -n argocd \
  cloud.google.com/neg='{"ingress": true}'
sed -i "s/<PUBLIC_DNS_NAME>/${PUBLIC_DNS_NAME}/g" argocd-server-managed-certificate.yaml
kubectl apply -f argocd-server-managed-certificate.yaml
sed -i "s/<PUBLIC_DNS_NAME>/${PUBLIC_DNS_NAME}/g" argocd-server-ingress.yaml
kubectl apply -f argocd-server-ingress.yaml
kubectl patch deployment argocd-server -n argocd -p "$(cat argocd-server.patch.yaml)" 
```

Once argocd server ingress is created, login using the CLI

```shell
kubectl wait ingress argocd-server-https-ingress --for=condition=available --timeout=600s -n argocd
```

```shell
ARGOCD_ADDR="argocd.${PUBLIC_DNS_NAME}"
# get default password
ARGOCD_DEFAULT_PASSWORD=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
argocd login $ARGOCD_ADDR --grpc-web
# change password
argocd account update-password
# for any issue, reset the password, edit the argocd-secret secret and update the admin.password field with a new bcrypt hash. You can use a site like https://www.browserling.com/tools/bcrypt to generate a new hash.
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {
    "admin.password": "<BCRYPT_HASH>",
    "admin.passwordMtime": "'$(date +%FT%T%Z)'"
  }}'
```

Create repositories, users and rbacs

```shell
sed -i "s,<GIT_REPOSITORY_URL>,$GIT_REPOSITORY_URL,g" argocd-configmap.yaml
kubectl apply -n argocd -f argocd-configmap.yaml
kubectl apply -n argocd -f argocd-rbac-configmap.yaml
```

Change demo user password

```shell
argocd account update-password --account demo --current-password "${ARGOCD_DEFAULT_PASSWORD}" --new-password "<NEW_PASSWORD>"
```

Generate an access token for argocd

```shell
AROGOCD_TOKEN=$(argocd account generate-token --account gitlab)
```

Save argocd token in secret manager

```shell
gcloud beta secrets create argocd-token --locations $GCP_REGION_DEFAULT --replication-policy user-managed
echo -n "${AROGOCD_TOKEN}" | gcloud beta secrets versions add argocd-token --data-file=-
```


# Scaleway

Install [sw-cli](https://github.com/scaleway/scaleway-cli)

```shell
scw init
```

Create a service account to allow kapsule to access GCR cluster

```shell
SW_SA_EMAIL=$(gcloud iam service-accounts --format='value(email)' create sw-gcr-auth-ro)
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} --member serviceAccount:$SW_SA_EMAIL --role roles/storage.objectViewer
```

**Now you can run the gitlab ci pipeline ! With the following Gitlab CI/CD Variables**

In `demo-infra` repo

```shell
GCP_PROJECT_ID=$GCP_PROJECT_ID
SW_PROJECT_NAME=$SW_PROJECT_NAME
VAULT_ADDR=$VAULT_ADDR
ENV=dev
```

In `demo-env` repo

```shell
GCP_PROJECT_ID=$GCP_PROJECT_ID
SW_PROJECT_NAME=$SW_PROJECT_NAME
ARGOCD_ADDR=$ARGOCD_ADDR
VAULT_ADDR=$VAULT_ADDR
ENV=dev
```

In `demo-app` repo

```shell
GCP_PROJECT_ID=$GCP_PROJECT_ID
```

# Documentation

- [Authenticating and Reading Secrets With Hashicorp Vault](https://docs.gitlab.com/ee/ci/examples/authenticating-with-hashicorp-vault/)
- [How to setup Vault with Kubernetes](https://deepsource.io/blog/setup-vault-kubernetes/)
- [HashiCorp Vault on GKE with Terraform](https://github.com/sethvargo/vault-on-gke)
- [GitOps in Kubernetes: How to do it with GitLab CI and Argo CD](https://medium.com/@andrew.kaczynski/gitops-in-kubernetes-argo-cd-and-gitlab-ci-cd-5828c8eb34d6)
- [ArgoCD User Management](https://argoproj.github.io/argo-cd/operator-manual/user-management/)
- [Google Cloud Registry (GCR) with external Kubernetes](http://docs.heptio.com/content/private-registries/pr-gcr.html)