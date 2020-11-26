FROM gcr.io/google.com/cloudsdktool/cloud-sdk:alpine
RUN gcloud components install kustomize kpt kubectl alpha beta

# install argocd
RUN curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')/argocd-linux-amd64
RUN chmod +x /usr/local/bin/argocd

# install vault
ENV VAULT_VERSION=1.6.0
RUN curl -sS "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" > vault.zip && \
    unzip vault.zip -d /usr/bin && \
    rm vault.zip

# install terraform
ENV TERRAFORM_VERSION=0.12.24
RUN curl -sS "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" > terraform.zip && \
    unzip terraform.zip -d /usr/bin && \
    rm terraform.zip

# Install sw cli 
ENV SCW_VERSION=2.2.2
RUN curl -o /usr/local/bin/scw -L "https://github.com/scaleway/scaleway-cli/releases/download/v${SCW_VERSION}/scw-${SCW_VERSION}-linux-x86_64"
RUN chmod +x /usr/local/bin/scw

RUN vault -v
RUN terraform -v
RUN argocd
RUN gcloud -v
RUN scw version

ARG GITLAB_SSH_KEY
ARG VAULT_ADDR
ARG VAULT_CA
ARG VAULT_TOKEN

RUN echo -n $VAULT_CA > /home/ca.pem
RUN sed -i 's/\\n/\n/g' /home/ca.pem

ENV GITLAB_SSH_KEY=$GITLAB_SSH_KEY
ENV VAULT_ADDR=$VAULT_ADDR
ENV VAULT_TOKEN=$VAULT_TOKEN
ENV VAULT_CAPATH="/home/ca.pem"
