#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

if [ -f "$ENV_FILE" ]; then
    echo "Carregando variáveis de ambiente de: $ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
else
    echo "Arquivo .env não encontrado. Usando valores padrão do script."
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Erro: comando obrigatório não encontrado: $1"
        exit 1
    fi
}

register_provider() {
    local namespace="$1"

    echo "Verificando provider $namespace..."
    local state
    state=$(az provider show --namespace "$namespace" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")

    if [ "$state" != "Registered" ]; then
        echo "Registrando provider $namespace..."
        az provider register --namespace "$namespace"

        until [ "$(az provider show --namespace "$namespace" --query registrationState -o tsv)" = "Registered" ]; do
            echo "Aguardando provider $namespace ficar Registered..."
            sleep 10
        done
    fi
}

set_github_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local repo="$3"

    if gh secret set "$secret_name" --body "$secret_value" --repo "$repo"; then
        echo "Secret $secret_name configurado em $repo"
    else
        echo "Aviso: não foi possível configurar o secret $secret_name em $repo."
        echo "Verifique se o usuário autenticado no GitHub CLI tem permissão WRITE/Admin no repositório."
        echo "Se necessário, cadastre manualmente em Settings → Secrets and variables → Actions."
    fi
}

require_command az
require_command gh
require_command openssl
require_command curl

az extension add --name communication --upgrade >/dev/null 2>&1 || true
az extension add --name application-insights --upgrade >/dev/null 2>&1 || true

register_provider "Microsoft.KeyVault"
register_provider "Microsoft.DBforPostgreSQL"
register_provider "Microsoft.Communication"
register_provider "Microsoft.Web"
register_provider "Microsoft.Storage"
register_provider "Microsoft.Network"
register_provider "Microsoft.OperationalInsights"
register_provider "Microsoft.Insights"

RG_NAME="${RG_NAME:-rg-feedback-platform}"
LOCATION="${LOCATION:-brazilsouth}"



VNET_NAME="${VNET_NAME:-vnet-feedback}"
VSUBNET_NAME="${VSUBNET_NAME:-snet-feedback}"
DB_SUBNET_NAME="${DB_SUBNET_NAME:-snet-feedback-postgres}"
DB_DNS_ZONE_NAME="${DB_DNS_ZONE_NAME:-feedback.private.postgres.database.azure.com}"

KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-feedback-platform}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stfeedbackprodbrs01}"

# database
DB_SERVER_NAME="${DB_SERVER_NAME:-pg-feedback-platform}"
DB_ADMIN_USER="${DB_ADMIN_USER:-feedback}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-SuaSenhaForteAqui123!}"

# communication service
COMMUNICATION_SERVICE_NAME="${COMMUNICATION_SERVICE_NAME:-acs-feedback-platform}"
EMAIL_SERVICE_NAME="${EMAIL_SERVICE_NAME:-aes-feedback-platform}"
EMAIL_DOMAIN_NAME="${EMAIL_DOMAIN_NAME:-AzureManagedDomain}"
ADMIN_EMAIL="${ADMIN_EMAIL:-ex.email@mail.com;email.admin@mail.com}"

# log analytics workspace
WORKSPACE_NAME="${WORKSPACE_NAME:-law-feedback-platform}"
APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-appi-feedback-platform}"

# github
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
TENANT_ID="${TENANT_ID:-$(az account show --query tenantId --output tsv)}"

# function app - login
FUNCTION_LOGIN_NAME="${FUNCTION_LOGIN_NAME:-func-feedback-platform-login}"
PRIVATE_SECRET_NAME="${PRIVATE_SECRET_NAME:-jwt-private-key}"
PUBLIC_SECRET_NAME="${PUBLIC_SECRET_NAME:-jwt-public-key}"
LOGIN_REPO="${LOGIN_REPO:-KervinCandido/az-func-feedback-login}"
GITHUB_LOGIN_APP_NAME="${GITHUB_LOGIN_APP_NAME:-github-actions-feedback-platform-login}"

# function app - core
FUNCTION_CORE_NAME="${FUNCTION_CORE_NAME:-func-feedback-platform-core}"
CORE_REPO="${CORE_REPO:-KervinCandido/az-func-feedback-core}"
GITHUB_CORE_APP_NAME="${GITHUB_CORE_APP_NAME:-github-actions-feedback-platform-core}"

# function app - report
FUNCTION_REPORT_NAME="${FUNCTION_REPORT_NAME:-func-feedback-platform-report}"
REPORT_REPO="${REPORT_REPO:-KervinCandido/az-func-feedback-report}"
GITHUB_REPORT_APP_NAME="${GITHUB_REPORT_APP_NAME:-github-actions-feedback-platform-report}"

RUN_REPORT_TRIGGER="${RUN_REPORT_TRIGGER:-false}"
RUN_CLEANUP="${RUN_CLEANUP:-false}"


# Criando o Resource Group
echo "Criando Resource Group: ${RG_NAME}"
az group create --name $RG_NAME --location $LOCATION

# Criando a vnet e vsub-net
echo "Criando vnet ${VNET_NAME} e vsub-net ${VSUBNET_NAME}"
az network vnet create --name $VNET_NAME --resource-group $RG_NAME --address-prefix 10.0.0.0/16 --subnet-name $VSUBNET_NAME --subnet-prefixes 10.0.0.0/24

# Habilitação do service-endpoints
echo "Habilitando service-endpoints da ${VNET_NAME} e vsub-net ${VSUBNET_NAME}"
az network vnet subnet update --name $VSUBNET_NAME \
    --vnet-name $VNET_NAME \
    --resource-group $RG_NAME \
    --service-endpoints Microsoft.Storage

echo "Criando subnet ${DB_SUBNET_NAME}"
az network vnet subnet create \
  --resource-group $RG_NAME \
  --vnet-name $VNET_NAME \
  --name $DB_SUBNET_NAME \
  --address-prefixes 10.0.1.0/24 \
  --delegations Microsoft.DBforPostgreSQL/flexibleServers

# Criando Azure Key Vault
echo "Criando key vault ${KEY_VAULT_NAME}"
az keyvault create --name $KEY_VAULT_NAME --resource-group $RG_NAME --location $LOCATION
az keyvault show \
    --name "$KEY_VAULT_NAME" \
    --resource-group "$RG_NAME" \
    --query id --output tsv > kv_id.txt

KV_URI=$(az keyvault show \
    --name "$KEY_VAULT_NAME" \
    --resource-group "$RG_NAME" \
    --query "properties.vaultUri" \
    --output tsv)

CURRENT_USER_ID=$(az ad signed-in-user show --query id --output tsv)

az role assignment create \
    --assignee "$CURRENT_USER_ID" \
    --role "Key Vault Secrets Officer" \
    --scope @kv_id.txt

# Criando Storage Account
echo "Criando storage account ${STORAGE_ACCOUNT_NAME}"
az storage account create --name $STORAGE_ACCOUNT_NAME \
    --location $LOCATION \
    --resource-group $RG_NAME \
    --sku Standard_LRS \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --default-action Allow

STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RG_NAME \
    --query connectionString \
    --output tsv)

# 1. Criar a Zona DNS Privada
echo "Criando private dns zone ${DB_DNS_ZONE_NAME}"
az network private-dns zone create \
  --resource-group $RG_NAME \
  --name $DB_DNS_ZONE_NAME

# 2. Vincular a Zona DNS à sua VNet para que as Functions consigam resolver o DNS do banco
echo "Vincular a Zona DNS à sua VNet para que as Functions consigam resolver o DNS do banco ${DB_DNS_ZONE_NAME}"
az network private-dns link vnet create \
  --resource-group $RG_NAME \
  --zone-name $DB_DNS_ZONE_NAME \
  --name "feedback-db-vnet-link" \
  --virtual-network $VNET_NAME \
  --registration-enabled false

# Criando Azure Database for PostgreSQL (Flexible Server)
echo "Criando servidor de postgresql ${DB_SERVER_NAME}"
az postgres flexible-server create \
    --resource-group $RG_NAME \
    --name $DB_SERVER_NAME \
    --location $LOCATION \
    --admin-user $DB_ADMIN_USER \
    --admin-password $DB_ADMIN_PASSWORD \
    --sku-name Standard_B2s \
    --tier Burstable \
    --version 18 \
    --vnet $VNET_NAME \
    --subnet $DB_SUBNET_NAME \
    --private-dns-zone $DB_DNS_ZONE_NAME \
    --yes

DB_HOST=$(az postgres flexible-server show --resource-group $RG_NAME --name $DB_SERVER_NAME --query fullyQualifiedDomainName --output tsv)
DB_JDBC_URL="jdbc:postgresql://$DB_HOST:5432/postgres?sslmode=require"

echo "Criando o Communication Service ${COMMUNICATION_SERVICE_NAME}"
az communication create \
    --name $COMMUNICATION_SERVICE_NAME \
    --resource-group $RG_NAME \
    --data-location "Brazil" \
    --location "Global"

echo "Criando o Communication Email Service ${EMAIL_SERVICE_NAME}"
az communication email create \
    --name $EMAIL_SERVICE_NAME \
    --resource-group $RG_NAME \
    --data-location "Brazil" \
    --location "Global"

echo "Criando o dominio $EMAIL_DOMAIN_NAME para o email"
az communication email domain create \
    --email-service-name $EMAIL_SERVICE_NAME \
    --name $EMAIL_DOMAIN_NAME \
    --resource-group $RG_NAME \
    --location "Global" \
    --domain-management "AzureManaged"

echo "Vinculando o domínio ${EMAIL_DOMAIN_NAME} de e-mail ao Communication Service ${COMMUNICATION_SERVICE_NAME}"
az communication email domain show \
    --email-service-name "$EMAIL_SERVICE_NAME" \
    --name "$EMAIL_DOMAIN_NAME" \
    --resource-group $RG_NAME \
    --query id --output tsv > dominio_id.txt

az communication update \
    --name $COMMUNICATION_SERVICE_NAME \
    --resource-group $RG_NAME \
    --linked-domains @dominio_id.txt

EMAIL_CONN_STR=$(az communication list-key \
    --name "$COMMUNICATION_SERVICE_NAME" \
    --resource-group "$RG_NAME" \
    --query primaryConnectionString \
    --output tsv)

EMAIL_DOMAIN=$(az communication email domain show \
    --email-service-name "$EMAIL_SERVICE_NAME" \
    --name "$EMAIL_DOMAIN_NAME" \
    --resource-group "$RG_NAME" \
    --query "mailFromSenderDomain" \
    --output tsv)

EMAIL_SENDER="donotreply@${EMAIL_DOMAIN}"

# echo "Criando Log Analytics Workspace ${WORKSPACE_NAME}"
az monitor log-analytics workspace create \
    --resource-group "$RG_NAME" \
    --workspace-name "$WORKSPACE_NAME" \
    --location "$LOCATION"

echo "Criando app-insights ${APP_INSIGHTS_NAME}"
az extension add --name application-insights
az monitor log-analytics workspace show \
    --resource-group "$RG_NAME" \
    --workspace-name "$WORKSPACE_NAME" \
    --query id --output tsv > workspace_id.txt

az monitor app-insights component create \
    --app "$APP_INSIGHTS_NAME" \
    --resource-group "$RG_NAME" \
    --location "$LOCATION" \
    --kind web \
    --application-type web \
    --workspace @workspace_id.txt

echo "Criando function ${FUNCTION_LOGIN_NAME}"
az functionapp create \
    --name "$FUNCTION_LOGIN_NAME" \
    --resource-group "$RG_NAME" \
    --storage-account "$STORAGE_ACCOUNT_NAME" \
    --functions-version 4 \
    --runtime java \
    --runtime-version "25.0" \
    --os-type Linux \
    --instance-memory 512 \
    --flexconsumption-location brazilsouth \
    --assign-identity "[system]" \
    --app-insights "$APP_INSIGHTS_NAME" \
    --vnet $VNET_NAME \
    --subnet $VSUBNET_NAME
echo "Configurando a QUARKUS_AZURE_KEYVAULT_SECRET_ENDPOINT"
az functionapp config appsettings set \
    --name "$FUNCTION_LOGIN_NAME" \
    --resource-group "$RG_NAME" \
    --settings "QUARKUS_AZURE_KEYVAULT_SECRET_ENDPOINT=$KV_URI"

echo "Adicionado RBAC de para function conseguir ler os secrets"
PRINCIPAL_ID=$(az functionapp identity assign \
    --name "$FUNCTION_LOGIN_NAME" \
    --resource-group "$RG_NAME" \
    --query principalId \
    --output tsv)

az role assignment create \
    --assignee "$PRINCIPAL_ID" \
    --role "Key Vault Secrets User" \
    --scope @kv_id.txt

echo "Adicionando as chaves privada e publica no key vault"
openssl genpkey -algorithm RSA -out private_key.pem -pkeyopt rsa_keygen_bits:2048

openssl rsa -pubout -in private_key.pem -out public_key.pem

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$PRIVATE_SECRET_NAME" \
    --value "@private_key.pem"

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$PUBLIC_SECRET_NAME" \
    --value "@public_key.pem"

echo "Verificando App Registration no Entra ID..."
LOGIN_CLIENT_ID=$(az ad app list --display-name "$GITHUB_LOGIN_APP_NAME" --query "[0].appId" --output tsv | tr -d '\r')

if [ -z "$LOGIN_CLIENT_ID" ]; then
    echo "Criando App Registration dedicado para o GitHub..."
    LOGIN_CLIENT_ID=$(az ad app create --display-name "$GITHUB_LOGIN_APP_NAME" --query appId --output tsv | tr -d '\r')
    
    echo "Criando Service Principal..."
    az ad sp create --id "$LOGIN_CLIENT_ID"
fi

# 3. Configuração da Credencial Federada (OIDC)
echo "Configurando credencial federada (Aperto de mão GitHub <> Azure)..."
cat <<EOF > login_fed_creds.json
{
    "name": "github-actions-login-func",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:${LOGIN_REPO}:ref:refs/heads/main",
    "description": "Permite o GitHub fazer login como a Function",
    "audiences": ["api://AzureADTokenExchange"]
}
EOF

# Se a credencial federada já existir, removemos para garantir que seja recriada com as configurações corretas
az ad app federated-credential delete \
    --id "$LOGIN_CLIENT_ID" \
    --federated-credential-id "github-actions-login-func" \
    2>/dev/null || true

az ad app federated-credential create \
    --id "$LOGIN_CLIENT_ID" \
    --parameters @login_fed_creds.json

# 4. Atribuição de Permissão (RBAC) isolada na Function App
echo "Garantindo permissão de Contributor apenas no escopo da Function..."
az functionapp show --name "${FUNCTION_LOGIN_NAME}" --resource-group "$RG_NAME" --query id --output tsv | tr -d '\r' > function_login_scope.txt

az role assignment create \
    --assignee "$LOGIN_CLIENT_ID" \
    --role "Contributor" \
    --scope @function_login_scope.txt

echo "Injetando credenciais no GitHub Secrets..."
set_github_secret "LOGIN_CLIENT_ID" "$LOGIN_CLIENT_ID" "$LOGIN_REPO"
set_github_secret "TENANT_ID" "$TENANT_ID" "$LOGIN_REPO"
set_github_secret "SUBSCRIPTION_ID" "$SUBSCRIPTION_ID" "$LOGIN_REPO"

# function core
echo "Criando function ${FUNCTION_CORE_NAME}"
az functionapp create \
    --name "$FUNCTION_CORE_NAME" \
    --resource-group "$RG_NAME" \
    --storage-account "$STORAGE_ACCOUNT_NAME" \
    --functions-version 4 \
    --runtime java \
    --runtime-version "25.0" \
    --os-type Linux \
    --instance-memory 512 \
    --flexconsumption-location brazilsouth \
    --assign-identity "[system]" \
    --app-insights "$APP_INSIGHTS_NAME" \
    --vnet $VNET_NAME \
    --subnet $VSUBNET_NAME
echo "Configurando a QUARKUS_AZURE_KEYVAULT_SECRET_ENDPOINT"
az functionapp config appsettings set \
    --name "$FUNCTION_CORE_NAME" \
    --resource-group "$RG_NAME" \
    --settings "QUARKUS_AZURE_KEYVAULT_SECRET_ENDPOINT=$KV_URI"

echo "Configurando o FEEDBACK_DB_KIND para postgresql"
az functionapp config appsettings set \
    --name "$FUNCTION_CORE_NAME" \
    --resource-group "$RG_NAME" \
    --settings "FEEDBACK_DB_KIND=postgresql"

echo "Adicionado RBAC de para function conseguir ler os secrets"
PRINCIPAL_ID=$(az functionapp identity assign \
    --name "$FUNCTION_CORE_NAME" \
    --resource-group "$RG_NAME" \
    --query principalId \
    --output tsv)

az role assignment create \
    --assignee "$PRINCIPAL_ID" \
    --role "Key Vault Secrets User" \
    --scope @kv_id.txt

# acesso ao banco para function core
az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "FeedbackDBUrl" \
    --value "$DB_JDBC_URL"

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "FeedbackDBUser" \
    --value "$DB_ADMIN_USER"

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "FeedbackDBPassword" \
    --value "$DB_ADMIN_PASSWORD"

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "FeedbackEmailConnectionString" \
    --value "$EMAIL_CONN_STR"

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "FeedbackAdminEmailList" \
    --value "$ADMIN_EMAIL"

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "FeedbackEmailSenderAddress" \
    --value "$EMAIL_SENDER"

az functionapp config appsettings set \
    --name "$FUNCTION_CORE_NAME" \
    --resource-group "$RG_NAME" \
    --settings "EMAIL_SUBJECT=Feedback de insatisfação recebido - FeedBack Platform"


# echo "Verificando App Registration no Entra ID..."
CORE_CLIENT_ID=$(az ad app list --display-name "$GITHUB_CORE_APP_NAME" --query "[0].appId" --output tsv | tr -d '\r')

if [ -z "$CORE_CLIENT_ID" ]; then
    echo "Criando App Registration dedicado para o GitHub..."
    CORE_CLIENT_ID=$(az ad app create --display-name "$GITHUB_CORE_APP_NAME" --query appId --output tsv | tr -d '\r')
    
    echo "Criando Service Principal..."
    az ad sp create --id "$CORE_CLIENT_ID"
fi

# # 3. Configuração da Credencial Federada (OIDC)
echo "Configurando credencial federada (Aperto de mão GitHub <> Azure)..."
cat <<EOF > core_fed_creds.json
{
    "name": "github-actions-core-func",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:${CORE_REPO}:ref:refs/heads/main",
    "description": "Permite o GitHub fazer login como a Function",
    "audiences": ["api://AzureADTokenExchange"]
}
EOF

# Se a credencial federada já existir, removemos para garantir que seja recriada com as configurações corretas
az ad app federated-credential delete \
    --id "$CORE_CLIENT_ID" \
    --federated-credential-id "github-actions-core-func" \
    2>/dev/null || true

az ad app federated-credential create \
    --id "$CORE_CLIENT_ID" \
    --parameters @core_fed_creds.json

# # 4. Atribuição de Permissão (RBAC) isolada na Function App
echo "Garantindo permissão de Contributor apenas no escopo da Function..."
az functionapp show --name "${FUNCTION_CORE_NAME}" --resource-group "$RG_NAME" --query id --output tsv | tr -d '\r' > function_core_scope.txt

az role assignment create \
    --assignee "$CORE_CLIENT_ID" \
    --role "Contributor" \
    --scope @function_core_scope.txt

echo "Injetando credenciais no GitHub Secrets..."
set_github_secret "CORE_CLIENT_ID" "$CORE_CLIENT_ID" "$CORE_REPO"
set_github_secret "TENANT_ID" "$TENANT_ID" "$CORE_REPO"
set_github_secret "SUBSCRIPTION_ID" "$SUBSCRIPTION_ID" "$CORE_REPO"


# function report
echo "Criando function ${FUNCTION_REPORT_NAME}"
az functionapp create \
    --name "$FUNCTION_REPORT_NAME" \
    --resource-group "$RG_NAME" \
    --storage-account "$STORAGE_ACCOUNT_NAME" \
    --functions-version 4 \
    --runtime java \
    --runtime-version "25.0" \
    --os-type Linux \
    --instance-memory 512 \
    --flexconsumption-location brazilsouth \
    --assign-identity "[system]" \
    --app-insights "$APP_INSIGHTS_NAME" \
    --vnet $VNET_NAME \
    --subnet $VSUBNET_NAME

echo "Configurando a QUARKUS_AZURE_KEYVAULT_SECRET_ENDPOINT"
az functionapp config appsettings set \
    --name "$FUNCTION_REPORT_NAME" \
    --resource-group "$RG_NAME" \
    --settings "QUARKUS_AZURE_KEYVAULT_SECRET_ENDPOINT=$KV_URI"

echo "Configurando o FEEDBACK_DB_KIND para postgresql"
az functionapp config appsettings set \
    --name "$FUNCTION_REPORT_NAME" \
    --resource-group "$RG_NAME" \
    --settings "FEEDBACK_DB_KIND=postgresql"

echo "Adicionado RBAC de para function conseguir ler os secrets"
PRINCIPAL_ID=$(az functionapp identity assign \
    --name "$FUNCTION_REPORT_NAME" \
    --resource-group "$RG_NAME" \
    --query principalId \
    --output tsv)

az role assignment create \
    --assignee "$PRINCIPAL_ID" \
    --role "Key Vault Secrets User" \
    --scope @kv_id.txt

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "FeedbackReportStorageConnectionString" \
    --value "$STORAGE_CONNECTION_STRING"

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "FeedbackReportContainerName" \
    --value "feedback-reports"

REPORT_CLIENT_ID=$(az ad app list --display-name "$GITHUB_REPORT_APP_NAME" --query "[0].appId" --output tsv | tr -d '\r')

if [ -z "$REPORT_CLIENT_ID" ]; then
    echo "Criando App Registration dedicado para o GitHub..."
    REPORT_CLIENT_ID=$(az ad app create --display-name "$GITHUB_REPORT_APP_NAME" --query appId --output tsv | tr -d '\r')
    
    echo "Criando Service Principal..."
    az ad sp create --id "$REPORT_CLIENT_ID"
fi

# # 3. Configuração da Credencial Federada (OIDC)
echo "Configurando credencial federada (Aperto de mão GitHub <> Azure)..."
cat <<EOF > report_fed_creds.json
{
    "name": "github-actions-report-func",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:${REPORT_REPO}:ref:refs/heads/main",
    "description": "Permite o GitHub fazer login como a Function",
    "audiences": ["api://AzureADTokenExchange"]
}
EOF

# Se a credencial federada já existir, removemos para garantir que seja recriada com as configurações corretas
az ad app federated-credential delete \
    --id "$REPORT_CLIENT_ID" \
    --federated-credential-id "github-actions-report-func" \
    2>/dev/null || true

az ad app federated-credential create \
    --id "$REPORT_CLIENT_ID" \
    --parameters @report_fed_creds.json

# # 4. Atribuição de Permissão (RBAC) isolada na Function App
echo "Garantindo permissão de Contributor apenas no escopo da Function..."
az functionapp show --name "${FUNCTION_REPORT_NAME}" --resource-group "$RG_NAME" --query id --output tsv | tr -d '\r' > function_report_scope.txt

az role assignment create \
    --assignee "$REPORT_CLIENT_ID" \
    --role "Contributor" \
    --scope @function_report_scope.txt

echo "Injetando credenciais no GitHub Secrets..."
set_github_secret "REPORT_CLIENT_ID" "$REPORT_CLIENT_ID" "$REPORT_REPO"
set_github_secret "TENANT_ID" "$TENANT_ID" "$REPORT_REPO"
set_github_secret "SUBSCRIPTION_ID" "$SUBSCRIPTION_ID" "$REPORT_REPO"

# exemplo trigger function de report
if [ "$RUN_REPORT_TRIGGER" = "true" ]; then
    echo "Executando gatilho da Function Report..."

    curl -X POST \
      -H "Content-Type: application/json" \
      -H "x-functions-key: $(az functionapp keys list \
          --name "$FUNCTION_REPORT_NAME" \
          --resource-group "$RG_NAME" \
          --query "masterKey" \
          --output tsv)" \
      -d '{"input": ""}' \
      "https://${FUNCTION_REPORT_NAME}.azurewebsites.net/admin/functions/func-feedback-report"
else
    echo "RUN_REPORT_TRIGGER=false. Pulando execução do gatilho da Function Report."
fi


if [ "$RUN_CLEANUP" = "true" ]; then
    echo "Executando limpeza de arquivos temporários e variáveis locais..."

    rm -f private_key.pem public_key.pem kv_id.txt
    rm -f function_login_scope.txt function_core_scope.txt function_report_scope.txt
    rm -f login_fed_creds.json core_fed_creds.json report_fed_creds.json
    rm -f workspace_id.txt dominio_id.txt

    unset RG_NAME
    unset LOCATION
    unset VNET_NAME
    unset VSUBNET_NAME
    unset DB_SUBNET_NAME
    unset DB_DNS_ZONE_NAME
    unset KEY_VAULT_NAME
    unset STORAGE_ACCOUNT_NAME
    unset DB_SERVER_NAME
    unset DB_ADMIN_USER
    unset DB_ADMIN_PASSWORD
    unset DB_HOST
    unset DB_JDBC_URL
    unset COMMUNICATION_SERVICE_NAME
    unset EMAIL_SERVICE_NAME
    unset EMAIL_DOMAIN_NAME
    unset EMAIL_DOMAIN
    unset EMAIL_SENDER
    unset EMAIL_CONN_STR
    unset ADMIN_EMAIL
    unset WORKSPACE_NAME
    unset APP_INSIGHTS_NAME
    unset SUBSCRIPTION_ID
    unset TENANT_ID
    unset CURRENT_USER_ID
    unset FUNCTION_LOGIN_NAME
    unset PRIVATE_SECRET_NAME
    unset PUBLIC_SECRET_NAME
    unset LOGIN_REPO
    unset GITHUB_LOGIN_APP_NAME
    unset LOGIN_CLIENT_ID
    unset FUNCTION_CORE_NAME
    unset CORE_REPO
    unset GITHUB_CORE_APP_NAME
    unset CORE_CLIENT_ID
    unset FUNCTION_REPORT_NAME
    unset REPORT_REPO
    unset GITHUB_REPORT_APP_NAME
    unset REPORT_CLIENT_ID
    unset PRINCIPAL_ID
    unset KV_URI
    unset STORAGE_CONNECTION_STRING
else
    echo "RUN_CLEANUP=false. Arquivos temporários preservados para validação/debug."
fi



