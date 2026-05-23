# INFRA - Azure

Orientações e componentes para a criação, provisionamento e replicação automatizada da infraestrutura do sistema (IaC).

## Componentes de Infraestrutura

### 1. Core & Grupo de Recursos
* **Resource Group:** Agrupamento lógico de todos os recursos do ambiente (ex: dev, staging, prod).

### 2. Rede & Segurança (Networking & Security)
* **Virtual Network (VNet) & Subnets:** Isolamento de rede para os recursos internos.
* **Key Vault:** Armazenamento seguro de segredos, strings de conexão do banco de dados e chaves de API.
  * *Nota: Acesso restrito via Service Principal/Managed Identity e integrado à VNet.*

### 3. Armazenamento & Dados (Storage & Databases)
* **Storage Account:** Armazenamento de blobs (arquivos, uploads) e suporte interno para a execução das Function Apps.
* **Azure Database for PostgreSQL (Flexible Server):** Banco de dados relacional gerenciado para persistência de dados.

### 4. Comunicação (Communication Services)
* **Communication Service:** Plataforma de comunicação para o envio de notificações.
* **Email Communication Service:** Serviço especializado e domínio configurado para o disparo de e-mails transacionais.

### 5. Monitoramento & Observabilidade
* **Log Analytics Workspace:** Repositório central de logs do ambiente.
* **Application Insights:** Monitoramento de performance (APM), tracing de requisições e logs de erro das Function Apps.

### 6. Computação (Serverless)
* **Function Apps:** Execução baseada em eventos e arquitetura serverless, dividida em três escopos de microsserviços:
  * `fn-login`: Autenticação e autorização.
  * `fn-core`: Regras de negócio centrais do sistema.
  * `fn-report`: Processamento e geração de relatórios.

## Passo a passo

Antes de iniciar é necessario instalar o `azure CLI`, outra opção usar o `clould shell` do portal da azure. Os comandos a seguir utilizam a sintaxe bash.

1. Fazendo Login
    ``` pwsh
    az login
    ```
2. Criando variável para facilitar ajustes nos nomes/valores utilizados
    ```bash
    RG_NAME="rg-feedback-platform"
    LOCATION="brazilsouth"
    VNET_NAME="vnet-feedback"
    VSUBNET_NAME="snet-feedback"
    DB_SUBNET_NAME="snet-feedback-postgres"
    DB_DNS_ZONE_NAME="feedback.private.postgres.database.azure.com"
    KEY_VAULT_NAME="kv-feedback-platform"
    STORAGE_ACCOUNT_NAME="stfeedbackprodbrs01"
    DB_SERVER_NAME="pg-feedback-platform"
    DB_ADMIN_USER="feedback"
    DB_ADMIN_PASSWORD="SuaSenhaForteAqui123!"
    COMMUNICATION_SERVICE_NAME="acs-feedback-platform"
    EMAIL_SERVICE_NAME="aes-feedback-platform"
    EMAIL_DOMAIN_NAME="AzureManagedDomain"
    ADMIN_EMAIL="ex.email@mail.com,  email.admin@mail.com"
    WORKSPACE_NAME="law-feedback-platform"
    APP_INSIGHTS_NAME="appi-feedback-platform"
    PLAN_NAME="plan-feedback-platform"
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    TENANT_ID=$(az account show --query tenantId --output tsv)
    FUNCTION_LOGIN_NAME="func-feedback-platform-login"
    PRIVATE_SECRET_NAME="jwt-private-key"
    PUBLIC_SECRET_NAME="jwt-public-key"
    LOGIN_REPO="KervinCandido/az-func-feedback-login"
    GITHUB_LOGIN_APP_NAME="github-actions-feedback-platform-login"
    FUNCTION_CORE_NAME="func-feedback-platform-core"
    CORE_REPO="KervinCandido/az-func-feedback-core"
    GITHUB_CORE_APP_NAME="github-actions-feedback-platform-core"
    FUNCTION_REPORT_NAME="func-feedback-platform-report"
    REPORT_REPO="KervinCandido/az-func-feedback-report"
    GITHUB_REPORT_APP_NAME="github-actions-feedback-platform-report"
    ```
3. Criando o **Resource Group**
    ``` pwsh
    az group create --name $RG_NAME --location $LOCATION
    ```
4. Criando e configurando a vnet e vsub-net
    - Criando a vnet e vsub-net
    ``` pwsh
    az network vnet create --name $VNET_NAME --resource-group $RG_NAME --address-prefix 10.0.0.0/16 --subnet-name $VSUBNET_NAME --subnet-prefixes 10.0.0.0/24
    ```
    - Habilitação do service-endpoints. O Service Endpoint é uma conexão segura e direta entre sua rede virtual (VNET) e serviços Azure, mantendo o tráfego dentro da rede privada da Microsoft e fora da internet pública.
    ``` pwsh
    az network vnet subnet update --name $VSUBNET_NAME --vnet-name $VNET_NAME --resource-group $RG_NAME --service-endpoints Microsoft.Storage
    ```
5. Criando e configurando o Azure Key Vault
    1. Criando key vault
        ``` pwsh
        az keyvault create --name $KEY_VAULT_NAME --resource-group $RG_NAME --location $LOCATION
        az keyvault show \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RG_NAME" \
            --query id --output tsv > kv_id.txt
        ```
    2. Permissão para usuário logado gerencriar segredos
        ``` pwsh
        CURRENT_USER_ID=$(az ad signed-in-user show --query id --output tsv)
        ```
    3. Guardando Id e URI para passos posteriores
        ``` pwsh
        az role assignment create \
            --assignee "$CURRENT_USER_ID" \
            --role "Key Vault Secrets Officer" \
            --scope @kv_id.txt
    
        KV_URI=$(az keyvault show \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RG_NAME" \
            --query "properties.vaultUri" \
            --output tsv)
        ```
6. Criando Storage Account
    ``` pwsh
    az storage account create --name $STORAGE_ACCOUNT_NAME \
        --location $LOCATION \
        --resource-group $RG_NAME \
        --sku Standard_LRS \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2 \
        --default-action Deny \
        --vnet-name $VNET_NAME --subnet $VSUBNET_NAME
    ```
7. Criando Azure Database for PostgreSQL (Flexible Server)
    ``` pwsh
    az postgres flexible-server create \
        --resource-group $RG_NAME \
        --name $DB_SERVER_NAME \
        --location $LOCATION \
        --admin-user $DB_ADMIN_USER \
        --admin-password $DB_ADMIN_PASSWORD \
        --sku-name Standard_B2s \
        --tier Burstable \
        --version 18.3 \
        --public-access All
    ```
8. Criando o Communication Service
    ``` pwsh
    az communication create \
    --name $COMMUNICATION_SERVICE_NAME \
    --resource-group $RG_NAME \
    --data-location "Brazil" \
    --location "Global"
    ```
9. Criando o Communication Email Service
    ``` pwsh
    az communication email create \
        --name $EMAIL_SERVICE_NAME \
        --resource-group $RG_NAME \
        --data-location "Brazil" \
        --location "Global"
    ```
10. Criando o dominio para o email
    ``` pwsh
    az communication email domain create \
        --email-service-name $EMAIL_SERVICE_NAME \
        --name $EMAIL_DOMAIN_NAME \
        --resource-group $RG_NAME \
        --location "Global" \
        --domain-management "AzureManaged"
    ```
11. Vinculando o domínio de e-mail ao Communication Service principal
    ``` pwsh
    az communication email domain show \
    --email-service-name "aes-feedback-platform" \
    --name "AzureManagedDomain" \
    --resource-group "rg-feedback-platform" \
    --query id --output tsv > dominio_id.txt

    az communication update \
        --name $COMMUNICATION_SERVICE_NAME \
        --resource-group $RG_NAME \
        --linked-domains @dominio_id.txt

    rm dominio_id.txt
    ```
12. Criando Log Analytics Workspace
    ``` pwsh
    az monitor log-analytics workspace create \
        --resource-group "$RG_NAME" \
        --workspace-name "$WORKSPACE_NAME" \
        --location "$LOCATION"
    ```
13. Application Insights
    ``` pwsh
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

    rm workspace_id.txt
    ```
14. Criando functionapp plan
    ``` pwsh
    az functionapp plan create \
        --name "$PLAN_NAME" \
        --resource-group "$RG_NAME" \
        --location "$LOCATION" \
        --sku FC1 \
        --is-linux true
    ```
15. Function Apps (Login)
    1. Criando Function
        ``` pwsh
        az functionapp create \
            --name "$FUNCTION_LOGIN_NAME" \
            --resource-group "$RG_NAME" \
            --storage-account "$STORAGE_ACCOUNT_NAME" \
            --app-insights "$APP_INSIGHTS_NAME" \
            --functions-version 4 \
            --plan "$PLAN_NAME" \
            --runtime java \
            --runtime-version 25 \
            --os-type Linux \
            --vnet $VNET_NAME \ 
            --subnet $VSUBNET_NAME \
            --instance-memory 512

        az functionapp identity assign \
            --name "$FUNCTION_LOGIN_NAME" \
            --resource-group "$RG_NAME"
        ```
    2. Configurando váriaveis de ambiente
        ``` pwsh
        KV_URI=$(az keyvault show \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RG_NAME" \
            --query "properties.vaultUri" \
            --output tsv)
        az functionapp config appsettings set \
            --name "$FUNCTION_LOGIN_NAME" \
            --resource-group "$RG_NAME" \
            --settings "QUARKUS_AZURE_KEYVAULT_SECRET_ENDPOINT=$KV_URI"
        ```
    3. Configurando permissão para ler o key vault
        ``` pwsh
        PRINCIPAL_ID=$(az functionapp identity assign \
            --name "$FUNCTION_LOGIN_NAME" \
            --resource-group "$RG_NAME" \
            --query principalId \
            --output tsv)
        
        az keyvault show \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RG_NAME" \
            --query id --output tsv > kv_id.txt

        az role assignment create \
            --assignee "$PRINCIPAL_ID" \
            --role "Key Vault Secrets User" \
            --scope @kv_id.txt

        rm kv_id.txt
        ```
    4. Adicionando chaves pública e privada no key vault
        ``` pwsh
        # Caso não tenha as chaves
        openssl genpkey -algorithm RSA -out private_key.pem -pkeyopt rsa_keygen_bits:2048

        openssl rsa -pubout -in private_key.pem -out public_key.pem

        az keyvault secret set \
            --vault-name "$KEY_VAULT_NAME" \
            --name "$PRIVATE_SECRET_NAME" \
            --file private_key.pem
        
        az keyvault secret set \
            --vault-name "$KEY_VAULT_NAME" \
            --name "$PUBLIC_SECRET_NAME" \
            --file public_key.pem
        
        rm private_key.pem public_key.pem
        ```
    5. Configurando deploy automático da aplicação. Repositório: [az-func-feedback-login](https://github.com/KervinCandido/az-func-feedback-login).
    Para criação dos secrets do github é necessario está  logado no github cli, também é possivel criar as secrets view web.
        ``` pwsh
        GITHUB_APP_NAME="github-actions-feedback-platform-login"

        #Verificando App Registration no Entra ID...
        LOGIN_CLIENT_ID=$(az ad app list --display-name "$GITHUB_APP_NAME" --query "[0].appId" --output tsv | tr -d '\r')

        if [ -z "$LOGIN_CLIENT_ID" ]; then
            #Criando App Registration dedicado para o GitHub...
            LOGIN_CLIENT_ID=$(az ad app create --display-name "$GITHUB_APP_NAME" --query appId --output tsv | tr -d '\r')
            
            #"Criando Service Principal...
            az ad sp create --id "$LOGIN_CLIENT_ID"
        fi

        # Configuração da Credencial Federada (OIDC)
        # Configurando credencial federada (Aperto de mão GitHub <> Azure)...
        cat <<EOF > fed_creds.json
        {
            "name": "github-actions-login-func",
            "issuer": "https://token.actions.githubusercontent.com",
            "subject": "repo:${LOGIN_REPO}:ref:refs/heads/main",
            "description": "Permite o GitHub fazer login como a Function",
            "audiences": ["api://AzureADTokenExchange"]
        }
        EOF

        az ad app federated-credential create \
            --id "$LOGIN_CLIENT_ID" \
            --parameters @fed_creds.json

        # Atribuição de Permissão (RBAC) isolada na Function App
        # Garantindo permissão de Contributor apenas no escopo da Function...
        az functionapp show --name "${FUNCTION_LOGIN_NAME}" --resource-group "rg-feedback-platform" --query id --output tsv | tr -d '\r' > function_login_scope.txt

        az role assignment create \
            --assignee "$LOGIN_CLIENT_ID" \
            --role "Contributor" \
            --scope @function_login_scope.txt

        #Injetando credenciais no GitHub Secrets...
        gh secret set LOGIN_CLIENT_ID --body "$LOGIN_CLIENT_ID" --repo $LOGIN_REPO
        gh secret set TENANT_ID --body "$TENANT_ID" --repo $LOGIN_REPO
        gh secret set SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo $LOGIN_REPO
        ```
16. Feedback Core
    ``` pwsh
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
    gh secret set CORE_CLIENT_ID --body "$CORE_CLIENT_ID" --repo $CORE_REPO
    gh secret set TENANT_ID --body "$TENANT_ID" --repo $CORE_REPO
    gh secret set SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo $CORE_REPO
    ```

    Aviso importante: Após configurar um repositório (com suas credenciais e segredos), é necessário rodar um build (por exemplo, disparar uma GitHub Action) para que seja feito o deploy da aplicação na Azure.

17. Report
    ``` pwsh
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
    gh secret set REPORT_CLIENT_ID --body "$REPORT_CLIENT_ID" --repo $REPORT_REPO
    gh secret set TENANT_ID --body "$TENANT_ID" --repo $REPORT_REPO
    gh secret set SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo $REPORT_REPO

    #exemplo trigger function de report
    curl -X POST \
      -H "Content-Type: application/json" \
      -H "x-functions-key: \$(az functionapp keys list --name func-feedback-platform-report --resource-group rg-feedback-platform --query "masterKey" --output tsv)" \
      -d '{"input": ""}' \
      https://func-feedback-platform-report.azurewebsites.net/admin/functions/func-feedback-report
    ```

    Aviso importante: Após configurar um repositório (com suas credenciais e segredos), é necessário rodar um build (por exemplo, disparar uma GitHub Action) para que seja feito o deploy da aplicação na Azure.

18. Limpeza
    ``` pwsh
    rm private_key.pem public_key.pem kv_id.txt 
    rm function_login_scope.txt function_core_scope.txt function_report_scope.txt
    rm login_fed_creds.json core_fed_creds.json report_fed_creds.json
    
    rm workspace_id.txt
    rm dominio_id.txt
    
    unset SUBSCRIPTION_ID
    unset TENANT_ID
    unset LOGIN_CLIENT_ID
    unset CORE_CLIENT_ID
    
    unset PRINCIPAL_ID
    unset KV_URI
    unset GITHUB_LOGIN_APP_NAME
    unset DB_HOST
    unset DB_JDBC_URL
    unset EMAIL_CONN_STR
    unset EMAIL_DOMAIN
    unset EMAIL_SENDER
    unset STORAGE_CONNECTION_STRING
    unset REPORT_CLIENT_ID
    ```