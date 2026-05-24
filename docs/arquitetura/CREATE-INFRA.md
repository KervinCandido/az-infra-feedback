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
  * `func-feedback-platform-login` (Login): Autenticação e autorização.
  * `func-feedback-platform-core` (Core): Regras de negócio centrais do sistema.
  * `func-feedback-platform-report` (Report): Processamento e geração de relatórios.

## Execução automatizada via script

Além da execução manual descrita abaixo, a infraestrutura pode ser criada automaticamente pelo script `scripts/create-infra.sh`.

Para isso, use o comando `cd` para entrar na pasta.
```bash
cd scripts
```
Então gere uma cópia do arquivo de exemplo `.env.example` e nomeie como `.env`
```bash
cp .env.example .env
```

Edite o `.env` com os nomes desejados para o ambiente e execute:

```bash
bash -n create-infra.sh
bash create-infra.sh
```

Por padrão, o script:

- carrega variáveis do `.env`, quando existir;
- registra automaticamente os providers necessários;
- cria os recursos de infraestrutura;
- configura Key Vault, Function Apps, RBAC, OIDC e tenta configurar os GitHub Secrets;
- não dispara a Function de relatório automaticamente;
- não remove arquivos temporários automaticamente.

> **Atenção:** o script configura os secrets do GitHub Actions nos repositórios definidos em `LOGIN_REPO`, `CORE_REPO` e `REPORT_REPO`.
> Em testes com ambientes alternativos, confira se esses repositórios estão corretos para evitar sobrescrever secrets dos repositórios oficiais.

> **Observação:** o script foi pensado para provisionar um ambiente novo. Para reexecuções, prefira usar nomes novos ou um Resource Group novo, pois alguns recursos da Azure podem não aceitar recriação/alteração quando já estão vinculados a outros serviços.

Para disparar a Function de relatório ao final da execução, defina no `.env`:

```bash
RUN_REPORT_TRIGGER="true"
```

Para remover os arquivos temporários ao final da execução, defina no `.env`:

```bash
RUN_CLEANUP="true"
```


## Passo a passo

Antes de iniciar, é necessário instalar/configurar:

- Azure CLI, com login feito via `az login`;
- GitHub CLI (`gh`), com login feito via `gh auth login`;
- OpenSSL;
- curl;
- Bash, Git Bash, WSL ou Azure Cloud Shell.

> Os comandos abaixo foram escritos para execução em Bash, Git Bash, WSL ou Azure Cloud Shell.
> Caso utilize PowerShell, será necessário adaptar a sintaxe de variáveis, quebras de linha e redirecionamentos.

1. Fazendo Login
    ```bash
    az login
    ```
2. Configuração de Variáveis de Ambiente
    Para facilitar os ajustes nos nomes e valores utilizados em toda a infraestrutura, defina as variáveis abaixo divididas por grupos de acordo com a finalidade descrita.

    * **2.1. Grupo de Recursos e Localização (Resource Group & Location)**
      Define o nome do grupo de recursos (onde todos os recursos serão agrupados logicamente na assinatura do Azure) e a região geográfica do datacenter onde serão implantados.
      ```bash
      RG_NAME="rg-feedback-platform"
      LOCATION="brazilsouth"
      ```

    * **2.2. Infraestrutura de Rede (Networking)**
      Variáveis para configurar a rede virtual (VNet), as sub-redes dedicadas para os recursos gerais e o banco de dados, além da zona DNS privada para resolução de nomes interna.
      ```bash
      VNET_NAME="vnet-feedback"
      VSUBNET_NAME="snet-feedback"
      DB_SUBNET_NAME="snet-feedback-postgres"
      DB_DNS_ZONE_NAME="feedback.private.postgres.database.azure.com"
      ```

    * **2.3. Segurança e Armazenamento (Key Vault & Storage)**
      Nomes do Key Vault (cofre de chaves utilizado para armazenar segredos e strings de conexão de forma segura) e da Storage Account (usada para blobs e arquivos de apoio às functions).

      Define os nomes do Key Vault e da Storage Account.
      > **Atenção:** os nomes de Key Vault e Storage Account precisam ser globalmente únicos na Azure.
      > Se algum comando retornar erro informando que o nome já está em uso, altere o sufixo dos nomes abaixo.

      ```bash
      KEY_VAULT_NAME="kv-feedback-seunome01"
      STORAGE_ACCOUNT_NAME="stfeedbackseunome01"
      ```

    * **2.4. Banco de Dados (Flexible PostgreSQL Server)**
      Configurações de criação do servidor gerenciado do PostgreSQL, definindo o nome do servidor, o usuário administrador e a respectiva senha forte de acesso.
      
      > **Atenção:** o nome do servidor PostgreSQL também precisa ser único na Azure.
      > Se o comando retornar erro informando que o nome já está em uso, altere o sufixo de `DB_SERVER_NAME`.

      ```bash
      DB_SERVER_NAME="pg-feedback-seunome01"
      DB_ADMIN_USER="feedback"
      DB_ADMIN_PASSWORD="SuaSenhaForteAqui123!"
      ```

    * **2.5. Serviços de Comunicação (Communication Services)**
      Variáveis para habilitar o envio automatizado de e-mails transacionais (como notificações) por meio do Azure Communication Services.

      > **Atenção:** o nome do Communication Service também pode precisar ser único na Azure.
      > Se o comando retornar `NameReservationTaken`, altere o sufixo de `COMMUNICATION_SERVICE_NAME`.

      ```bash
      COMMUNICATION_SERVICE_NAME="acs-feedback-seunome01"
      EMAIL_SERVICE_NAME="aes-feedback-seunome01"
      EMAIL_DOMAIN_NAME="AzureManagedDomain"
      ADMIN_EMAIL="ex.email@mail.com;email.admin@mail.com"
      ```

    * **2.6. Monitoramento e Diagnóstico (Observability)**
      Configurações dos serviços de log centralizados (Log Analytics Workspace) e de monitoramento de performance de aplicações (Application Insights) para rastrear telemetrias das Function Apps.
      ```bash
      WORKSPACE_NAME="law-feedback-platform"
      APP_INSIGHTS_NAME="appi-feedback-platform"
      ```

    * **2.7. Identificação da Assinatura Azure (Subscription & Tenant)**
      Define o ID da assinatura Azure e o ID do tenant usados na configuração do GitHub Actions.

      Para execução manual, obtenha os valores pelo Azure CLI:

      ```bash
      SUBSCRIPTION_ID=$(az account show --query id --output tsv)
      TENANT_ID=$(az account show --query tenantId --output tsv)
      ```

      > Caso esteja usando o script automatizado com `.env`, essas variáveis podem ser deixadas vazias:
      >
      > ```bash
      > SUBSCRIPTION_ID=""
      > TENANT_ID=""
      > ```
      >
      > Nesse caso, o script obtém automaticamente os valores com `az account show`.

    * **2.8. Microsserviço de Login (Function App - Login)**
      Nomes e segredos específicos do microsserviço de autenticação, chaves pública/privada de assinatura dos tokens JWT e credenciais de Integração Contínua vinculadas ao seu respectivo repositório no GitHub.

      > **Atenção:** o nome da Function App precisa ser globalmente único na Azure,
      > pois compõe o endereço público `*.azurewebsites.net`.
      > Se o comando retornar que o site já existe, altere o sufixo de `FUNCTION_LOGIN_NAME`.
  
      ```bash
      FUNCTION_LOGIN_NAME="func-feedback-seunome-login"
      PRIVATE_SECRET_NAME="jwt-private-key"
      PUBLIC_SECRET_NAME="jwt-public-key"
      LOGIN_REPO="KervinCandido/az-func-feedback-login"
      GITHUB_LOGIN_APP_NAME="github-actions-feedback-platform-login"
      ```

    * **2.9. Microsserviço Core (Function App - Core)**
      Configurações para a Function App central contendo as regras de negócio do ecossistema e dados de integração de CI/CD para deploy via GitHub Actions.

      > **Atenção:** o nome da Function App precisa ser globalmente único na Azure,
      > pois compõe o endereço público `*.azurewebsites.net`.
      > Se o comando retornar que o site já existe, altere o sufixo de `FUNCTION_CORE_NAME`.

      ```bash
      FUNCTION_CORE_NAME="func-feedback-seunome-core"
      CORE_REPO="KervinCandido/az-func-feedback-core"
      GITHUB_CORE_APP_NAME="github-actions-feedback-platform-core"
      ```

    * **2.10. Microsserviço de Relatórios (Function App - Report)**
      Configurações de criação do microsserviço de geração de relatórios e dados para implantação automática via GitHub Actions.
      
      > **Atenção:** o nome da Function App precisa ser globalmente único na Azure,
      > pois compõe o endereço público `*.azurewebsites.net`.
      > Se o comando retornar que o site já existe, altere o sufixo de `FUNCTION_REPORT_NAME`.

      ```bash
      FUNCTION_REPORT_NAME="func-feedback-seunome-report"
      REPORT_REPO="KervinCandido/az-func-feedback-report"
      GITHUB_REPORT_APP_NAME="github-actions-feedback-platform-report"
      ```

      > Após alterar qualquer variável, confirme o valor no terminal com `echo "$NOME_DA_VARIAVEL"` antes de executar os próximos comandos.
      > Se a variável já tiver sido definida anteriormente na mesma sessão, redefina-a para o novo valor antes de continuar.

3. Criando o **Resource Group**
    ```bash
    az group create --name $RG_NAME --location $LOCATION
    ```

4. Criando e configurando a vnet e vsub-net
    1. Criar a vnet e vsub-net
        ```bash
        az network vnet create --name $VNET_NAME --resource-group $RG_NAME --address-prefix 10.0.0.0/16 --subnet-name $VSUBNET_NAME --subnet-prefixes 10.0.0.0/24
        ```
    2. Habilitação do service-endpoints. O Service Endpoint é uma conexão segura e direta entre sua rede virtual (VNET) e serviços Azure, mantendo o tráfego dentro da rede privada da Microsoft e fora da internet pública.
        ```bash
        az network vnet subnet update --name $VSUBNET_NAME --vnet-name $VNET_NAME --resource-group $RG_NAME --service-endpoints Microsoft.Storage
        ```
    3. Criando subnet para PostgreSQL (delegada)
        ```bash
        az network vnet subnet create \
          --resource-group $RG_NAME \
          --vnet-name $VNET_NAME \
          --name $DB_SUBNET_NAME \
          --address-prefixes 10.0.1.0/24 \
          --delegations Microsoft.DBforPostgreSQL/flexibleServers
        ```

5. Criando e configurando o Azure Key Vault

    > **Importante:** o nome do Key Vault precisa ser globalmente único na Azure.
    > Caso o nome definido em `KEY_VAULT_NAME` já esteja em uso, o comando retornará o erro `VaultAlreadyExists`.
    > Nesse caso, altere a variável para um nome exclusivo, por exemplo:
    >
    > ```bash
    > KEY_VAULT_NAME="kv-feedback-seunome01"
    > ```

    1. Verificar/registrar o provider do Key Vault na assinatura

        Em algumas assinaturas novas, o namespace `Microsoft.KeyVault` pode ainda não estar registrado.
        Caso isso aconteça, o comando de criação do Key Vault retornará o erro `MissingSubscriptionRegistration`.

        ```bash
        az provider register --namespace Microsoft.KeyVault
        ```

        Aguarde até o estado ficar como `Registered`:

        ```bash
        az provider show \
            --namespace Microsoft.KeyVault \
            --query registrationState \
            --output tsv
        ```

        O retorno esperado é:

        ```text
        Registered
        ```

    2. Criar o Key Vault

        ```bash
        az keyvault create \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RG_NAME" \
            --location "$LOCATION"
        ```

    3. Guardar o ID do Key Vault para passos posteriores

        ```bash
        az keyvault show \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RG_NAME" \
            --query id \
            --output tsv > kv_id.txt
        ```

        Validação:

        ```bash
        cat kv_id.txt
        ```

    4. Obter o ID do usuário logado

        ```bash
        CURRENT_USER_ID=$(az ad signed-in-user show --query id --output tsv)

        echo "$CURRENT_USER_ID"
        ```

    5. Conceder permissão para o usuário logado gerenciar segredos

        ```bash
        az role assignment create \
            --assignee "$CURRENT_USER_ID" \
            --role "Key Vault Secrets Officer" \
            --scope @kv_id.txt
        ```

    6. Guardar a URI do Key Vault para passos posteriores

        ```bash
        KV_URI=$(az keyvault show \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RG_NAME" \
            --query "properties.vaultUri" \
            --output tsv)

        echo "$KV_URI"
        ```

6. Criando Storage Account

    > **Importante:** o nome da Storage Account também precisa ser globalmente único na Azure.
    > Caso o nome definido em `STORAGE_ACCOUNT_NAME` já esteja em uso, o comando retornará o erro `StorageAccountAlreadyTaken`.
    > Nesse caso, altere a variável para um nome exclusivo, usando apenas letras minúsculas e números, por exemplo:
    >
    > ```bash
    > STORAGE_ACCOUNT_NAME="stfeedbackseunome01"
    > ```

    1. Criar a Storage Account

        ```bash
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --location "$LOCATION" \
            --resource-group "$RG_NAME" \
            --sku Standard_LRS \
            --min-tls-version TLS1_2 \
            --allow-blob-public-access false \
            --default-action Allow
        ```

    2. Obter a String de Conexão do Storage Account

        ```bash
        STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RG_NAME" \
            --query connectionString \
            --output tsv)

        echo "Storage connection string obtida com sucesso."
        ```

        > **Atenção:** não exponha a string de conexão em logs, prints ou mensagens, pois ela contém a chave de acesso da Storage Account.

7. Criando a Zona DNS Privada e Vinculando à VNet
    1. Criar a Zona DNS Privada
        ```bash
        az network private-dns zone create \
          --resource-group $RG_NAME \
          --name $DB_DNS_ZONE_NAME
        ```
    2. Vincular a Zona DNS à sua VNet
        ```bash
        az network private-dns link vnet create \
          --resource-group $RG_NAME \
          --zone-name $DB_DNS_ZONE_NAME \
          --name "feedback-db-vnet-link" \
          --virtual-network $VNET_NAME \
          --registration-enabled false
        ```
        
8. Criando Azure Database for PostgreSQL (Flexible Server)
   > Em algumas assinaturas novas, o namespace `Microsoft.DBforPostgreSQL` pode ainda não estar registrado.
   > Caso o comando retorne `MissingSubscriptionRegistration`, registre o provider antes de criar o servidor.
   >
   > ```bash
   > az provider register --namespace Microsoft.DBforPostgreSQL
   >
   > az provider show \
   >     --namespace Microsoft.DBforPostgreSQL \
   >     --query registrationState \
   >     --output tsv
   > ```
   >
   > O retorno esperado é:
   >
   > ```text
   > Registered
   > ```

   1. Criar o servidor PostgreSQL
      ```bash
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
      ```

   2. Obter o host do banco e montar a URL JDBC

      ```bash
      DB_HOST=$(az postgres flexible-server show \
          --resource-group "$RG_NAME" \
          --name "$DB_SERVER_NAME" \
          --query fullyQualifiedDomainName \
          --output tsv)  
      DB_JDBC_URL="jdbc:postgresql://$DB_HOST:5432/postgres?sslmode=require"  
      echo "$DB_HOST"
      echo "$DB_JDBC_URL"
      ```

9.  Criando o Communication Service

    > Caso a extensão `communication` ainda não esteja instalada, execute:
    >
    > ```bash
    > az config set extension.dynamic_install_allow_preview=true
    > az extension add --name communication --upgrade
    > ```
    >
    > Caso receba o erro `NameReservationTaken`, altere `COMMUNICATION_SERVICE_NAME` para um nome exclusivo e execute novamente.

    ```bash
    az communication create \
        --name "$COMMUNICATION_SERVICE_NAME" \
        --resource-group "$RG_NAME" \
        --data-location "Brazil" \
        --location "Global"
    ```

10. Criando o Communication Email Service
    ```bash
    az communication email create \
        --name "$EMAIL_SERVICE_NAME" \
        --resource-group "$RG_NAME" \
        --data-location "Brazil" \
        --location "Global"
    ```

11. Criando o dominio para o email
    ```bash
    az communication email domain create \
        --email-service-name "$EMAIL_SERVICE_NAME" \
        --name "$EMAIL_DOMAIN_NAME" \
        --resource-group "$RG_NAME" \
        --location "Global" \
        --domain-management "AzureManaged"
    ```

12. Vinculando o domínio de e-mail e obtendo credenciais
    1. Obter o ID do domínio de e-mail
        ```bash
        az communication email domain show \
            --email-service-name "$EMAIL_SERVICE_NAME" \
            --name "$EMAIL_DOMAIN_NAME" \
            --resource-group "$RG_NAME" \
            --query id --output tsv > dominio_id.txt
        ```
    2. Vincular o domínio de e-mail ao Communication Service principal
        ```bash
        az communication update \
            --name "$COMMUNICATION_SERVICE_NAME" \
            --resource-group "$RG_NAME" \
            --linked-domains @dominio_id.txt
        ```
    3. Obter a String de Conexão do Communication Service
        ```bash
        EMAIL_CONN_STR=$(az communication list-key \
            --name "$COMMUNICATION_SERVICE_NAME" \
            --resource-group "$RG_NAME" \
            --query primaryConnectionString \
            --output tsv)
        ```
    4. Obter o domínio do remetente
        ```bash
        EMAIL_DOMAIN=$(az communication email domain show \
            --email-service-name "$EMAIL_SERVICE_NAME" \
            --name "$EMAIL_DOMAIN_NAME" \
            --resource-group "$RG_NAME" \
            --query "mailFromSenderDomain" \
            --output tsv)
        ```
    5. Definir o endereço de e-mail do remetente
        ```bash
        EMAIL_SENDER="donotreply@${EMAIL_DOMAIN}"
        ```

13. Criando Log Analytics Workspace
    ```bash
    az monitor log-analytics workspace create \
        --resource-group "$RG_NAME" \
        --workspace-name "$WORKSPACE_NAME" \
        --location "$LOCATION"
    ```

14. Application Insights
    1. Adicionar a extensão de Application Insights
        ```bash
        az extension add --name application-insights --upgrade
        ```
    2. Obter o ID do Log Analytics Workspace
        ```bash
        az monitor log-analytics workspace show \
            --resource-group "$RG_NAME" \
            --workspace-name "$WORKSPACE_NAME" \
            --query id --output tsv > workspace_id.txt
        ```
    3. Criar o componente Application Insights integrado ao workspace
        ```bash
        az monitor app-insights component create \
            --app "$APP_INSIGHTS_NAME" \
            --resource-group "$RG_NAME" \
            --location "$LOCATION" \
            --kind web \
            --application-type web \
            --workspace @workspace_id.txt
        ```
        
15. Function Apps (Login)
    1. Criar a Function App
        
        > Caso receba o erro `Website with given name ... already exists`, altere `FUNCTION_LOGIN_NAME`
        > para um nome exclusivo e execute novamente.
        
        ```bash
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
            --vnet "$VNET_NAME" \
            --subnet "$VSUBNET_NAME"
        ```

    2. Configurando variáveis de ambiente
        ```bash
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
        ```bash
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
        ```

    4. Adicionando chaves pública e privada no key vault
        ```bash
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
        ```

    5. Configurando deploy automático da aplicação. Repositório: [az-func-feedback-login](https://github.com/KervinCandido/az-func-feedback-login).
          
        Este passo cria uma aplicação no Microsoft Entra ID para permitir que o GitHub Actions faça deploy na Function App usando autenticação via OIDC, sem necessidade de senha fixa.

        ```bash
        LOGIN_CLIENT_ID=$(az ad app list --display-name "$GITHUB_LOGIN_APP_NAME" --query "[0].appId" --output tsv | tr -d '\r')

        if [ -z "$LOGIN_CLIENT_ID" ]; then
            LOGIN_CLIENT_ID=$(az ad app create --display-name "$GITHUB_LOGIN_APP_NAME" --query appId --output tsv | tr -d '\r')
            az ad sp create --id "$LOGIN_CLIENT_ID"
        fi

        cat <<EOF > login_fed_creds.json
        {
            "name": "github-actions-login-func",
            "issuer": "https://token.actions.githubusercontent.com",
            "subject": "repo:${LOGIN_REPO}:ref:refs/heads/main",
            "description": "Permite o GitHub fazer login como a Function",
            "audiences": ["api://AzureADTokenExchange"]
        }
        EOF

        az ad app federated-credential delete \
            --id "$LOGIN_CLIENT_ID" \
            --federated-credential-id "github-actions-login-func" \
            2>/dev/null || true

        az ad app federated-credential create \
            --id "$LOGIN_CLIENT_ID" \
            --parameters @login_fed_creds.json

        az functionapp show \
            --name "${FUNCTION_LOGIN_NAME}" \
            --resource-group "$RG_NAME" \
            --query id \
            --output tsv | tr -d '\r' > function_login_scope.txt

        az role assignment create \
            --assignee "$LOGIN_CLIENT_ID" \
            --role "Contributor" \
            --scope @function_login_scope.txt
        ```

        Depois, cadastre no GitHub Actions os identificadores necessários para o workflow autenticar na Azure:

        ```bash
        gh secret set LOGIN_CLIENT_ID --body "$LOGIN_CLIENT_ID" --repo "$LOGIN_REPO"
        gh secret set TENANT_ID --body "$TENANT_ID" --repo "$LOGIN_REPO"
        gh secret set SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo "$LOGIN_REPO"
        ```

        > **Observação sobre permissões no GitHub:**  
        > Os comandos `gh secret set` só funcionam se o usuário autenticado no GitHub CLI tiver permissão para gerenciar secrets do GitHub Actions no repositório informado.
        >
        > Caso o comando retorne erro `HTTP 403`, como:
        >
        > ```text
        > failed to fetch public key: HTTP 403
        > You must have repository read permissions or have the repository secrets fine-grained permission.
        > ```
        >
        > isso indica que a configuração da Azure foi criada corretamente, mas o usuário atual não possui permissão suficiente para gravar secrets no repositório.
        >
        > Nesse caso, o responsável pelo repositório deve cadastrar manualmente os secrets pela interface web do GitHub:
        >
        > ```text
        > Settings → Secrets and variables → Actions → New repository secret
        > ```
        >
        > Para o microsserviço de Login, cadastre:
        >
        > ```text
        > LOGIN_CLIENT_ID
        > TENANT_ID
        > SUBSCRIPTION_ID
        > ```
        >
        > Essa etapa é necessária para que o deploy automatizado via GitHub Actions consiga autenticar na Azure usando OIDC.

16. Feedback Core
    1. Criar a Function App    
        
        > Caso receba o erro `Website with given name ... already exists`, altere `FUNCTION_CORE_NAME`
        > para um nome exclusivo e execute novamente.
        
        ```bash
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
            --vnet "$VNET_NAME" \
            --subnet "$VSUBNET_NAME"
        ```
    2. Configurando variáveis de ambiente
        ```bash
        az functionapp config appsettings set \
            --name "$FUNCTION_CORE_NAME" \
            --resource-group "$RG_NAME" \
            --settings "QUARKUS_AZURE_KEYVAULT_SECRET_ENDPOINT=$KV_URI"

        az functionapp config appsettings set \
            --name "$FUNCTION_CORE_NAME" \
            --resource-group "$RG_NAME" \
            --settings "FEEDBACK_DB_KIND=postgresql"

        az functionapp config appsettings set \
            --name "$FUNCTION_CORE_NAME" \
            --resource-group "$RG_NAME" \
            --settings "EMAIL_SUBJECT=Feedback de insatisfação recebido - FeedBack Platform"
        ```

    3. Configurando permissão para ler o key vault
        ```bash
        PRINCIPAL_ID=$(az functionapp identity assign \
            --name "$FUNCTION_CORE_NAME" \
            --resource-group "$RG_NAME" \
            --query principalId \
            --output tsv)

        az role assignment create \
            --assignee "$PRINCIPAL_ID" \
            --role "Key Vault Secrets User" \
            --scope @kv_id.txt
        ```

    4. Adicionando segredos de conexão ao key vault
        ```bash
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
        ```

    5. Configurando deploy automático da aplicação. Repositório: [az-func-feedback-core](https://github.com/KervinCandido/az-func-feedback-core).
        
        Este passo cria uma aplicação no Microsoft Entra ID para permitir que o GitHub Actions faça deploy na Function App usando autenticação via OIDC, sem necessidade de senha fixa.

        ```bash
        CORE_CLIENT_ID=$(az ad app list --display-name "$GITHUB_CORE_APP_NAME" --query "[0].appId" --output tsv | tr -d '\r')

        if [ -z "$CORE_CLIENT_ID" ]; then
            CORE_CLIENT_ID=$(az ad app create --display-name "$GITHUB_CORE_APP_NAME" --query appId --output tsv | tr -d '\r')
            az ad sp create --id "$CORE_CLIENT_ID"
        fi

        cat <<EOF > core_fed_creds.json
        {
            "name": "github-actions-core-func",
            "issuer": "https://token.actions.githubusercontent.com",
            "subject": "repo:${CORE_REPO}:ref:refs/heads/main",
            "description": "Permite o GitHub fazer login como a Function",
            "audiences": ["api://AzureADTokenExchange"]
        }
        EOF

        az ad app federated-credential delete \
            --id "$CORE_CLIENT_ID" \
            --federated-credential-id "github-actions-core-func" \
            2>/dev/null || true

        az ad app federated-credential create \
            --id "$CORE_CLIENT_ID" \
            --parameters @core_fed_creds.json

        az functionapp show \
            --name "${FUNCTION_CORE_NAME}" \
            --resource-group "$RG_NAME" \
            --query id \
            --output tsv | tr -d '\r' > function_core_scope.txt

        az role assignment create \
            --assignee "$CORE_CLIENT_ID" \
            --role "Contributor" \
            --scope @function_core_scope.txt
        ```

        Depois, cadastre no GitHub Actions os identificadores necessários para o workflow autenticar na Azure:

        ```bash
        gh secret set CORE_CLIENT_ID --body "$CORE_CLIENT_ID" --repo "$CORE_REPO"
        gh secret set TENANT_ID --body "$TENANT_ID" --repo "$CORE_REPO"
        gh secret set SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo "$CORE_REPO"
        ```

        > **Observação sobre permissões no GitHub:**  
        > Os comandos `gh secret set` só funcionam se o usuário autenticado no GitHub CLI tiver permissão para gerenciar secrets do GitHub Actions no repositório informado.
        >
        > Caso o comando retorne erro `HTTP 403`, como:
        >
        > ```text
        > failed to fetch public key: HTTP 403
        > You must have repository read permissions or have the repository secrets fine-grained permission.
        > ```
        >
        > isso indica que a configuração da Azure foi criada corretamente, mas o usuário atual não possui permissão suficiente para gravar secrets no repositório.
        >
        > Nesse caso, o responsável pelo repositório deve cadastrar manualmente os secrets pela interface web do GitHub:
        >
        > ```text
        > Settings → Secrets and variables → Actions → New repository secret
        > ```
        >
        > Para o microsserviço Core, cadastre:
        >
        > ```text
        > CORE_CLIENT_ID
        > TENANT_ID
        > SUBSCRIPTION_ID
        > ```
        >
        > Essa etapa é necessária para que o deploy automatizado via GitHub Actions consiga autenticar na Azure usando OIDC.

17. Report
    1. Criar a Function App
        
        > Caso receba o erro `Website with given name ... already exists`, altere `FUNCTION_REPORT_NAME`
        > para um nome exclusivo e execute novamente.
        
        ```bash
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
            --vnet "$VNET_NAME" \
            --subnet "$VSUBNET_NAME"
        ```

    2. Configurando variáveis de ambiente
        ```bash
        az functionapp config appsettings set \
            --name "$FUNCTION_REPORT_NAME" \
            --resource-group "$RG_NAME" \
            --settings "QUARKUS_AZURE_KEYVAULT_SECRET_ENDPOINT=$KV_URI"

        az functionapp config appsettings set \
            --name "$FUNCTION_REPORT_NAME" \
            --resource-group "$RG_NAME" \
            --settings "FEEDBACK_DB_KIND=postgresql"
        ```

    3. Configurando permissão para ler o key vault
        ```bash
        PRINCIPAL_ID=$(az functionapp identity assign \
            --name "$FUNCTION_REPORT_NAME" \
            --resource-group "$RG_NAME" \
            --query principalId \
            --output tsv)

        az role assignment create \
            --assignee "$PRINCIPAL_ID" \
            --role "Key Vault Secrets User" \
            --scope @kv_id.txt
        ```

    4. Adicionando segredos de relatórios ao key vault
        ```bash
        az keyvault secret set \
            --vault-name "$KEY_VAULT_NAME" \
            --name "FeedbackReportStorageConnectionString" \
            --value "$STORAGE_CONNECTION_STRING"

        az keyvault secret set \
            --vault-name "$KEY_VAULT_NAME" \
            --name "FeedbackReportContainerName" \
            --value "feedback-reports"
        ```

    5. Configurando deploy automático da aplicação. Repositório: [az-func-feedback-report](https://github.com/KervinCandido/az-func-feedback-report).
        
        Este passo cria uma aplicação no Microsoft Entra ID para permitir que o GitHub Actions faça deploy na Function App usando autenticação via OIDC, sem necessidade de senha fixa.

        ```bash
        REPORT_CLIENT_ID=$(az ad app list --display-name "$GITHUB_REPORT_APP_NAME" --query "[0].appId" --output tsv | tr -d '\r')

        if [ -z "$REPORT_CLIENT_ID" ]; then
            REPORT_CLIENT_ID=$(az ad app create --display-name "$GITHUB_REPORT_APP_NAME" --query appId --output tsv | tr -d '\r')
            az ad sp create --id "$REPORT_CLIENT_ID"
        fi

        cat <<EOF > report_fed_creds.json
        {
            "name": "github-actions-report-func",
            "issuer": "https://token.actions.githubusercontent.com",
            "subject": "repo:${REPORT_REPO}:ref:refs/heads/main",
            "description": "Permite o GitHub fazer login como a Function",
            "audiences": ["api://AzureADTokenExchange"]
        }
        EOF

        az ad app federated-credential delete \
            --id "$REPORT_CLIENT_ID" \
            --federated-credential-id "github-actions-report-func" \
            2>/dev/null || true

        az ad app federated-credential create \
            --id "$REPORT_CLIENT_ID" \
            --parameters @report_fed_creds.json

        az functionapp show \
            --name "${FUNCTION_REPORT_NAME}" \
            --resource-group "$RG_NAME" \
            --query id \
            --output tsv | tr -d '\r' > function_report_scope.txt

        az role assignment create \
            --assignee "$REPORT_CLIENT_ID" \
            --role "Contributor" \
            --scope @function_report_scope.txt
        ```

        Depois, cadastre no GitHub Actions os identificadores necessários para o workflow autenticar na Azure:

        ```bash
        gh secret set REPORT_CLIENT_ID --body "$REPORT_CLIENT_ID" --repo "$REPORT_REPO"
        gh secret set TENANT_ID --body "$TENANT_ID" --repo "$REPORT_REPO"
        gh secret set SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo "$REPORT_REPO"
        ```

        > **Observação sobre permissões no GitHub:**  
        > Os comandos `gh secret set` só funcionam se o usuário autenticado no GitHub CLI tiver permissão para gerenciar secrets do GitHub Actions no repositório informado.
        >
        > Caso o comando retorne erro `HTTP 403`, como:
        >
        > ```text
        > failed to fetch public key: HTTP 403
        > You must have repository read permissions or have the repository secrets fine-grained permission.
        > ```
        >
        > isso indica que a configuração da Azure foi criada corretamente, mas o usuário atual não possui permissão suficiente para gravar secrets no repositório.
        >
        > Nesse caso, o responsável pelo repositório deve cadastrar manualmente os secrets pela interface web do GitHub:
        >
        > ```text
        > Settings → Secrets and variables → Actions → New repository secret
        > ```
        >
        > Para o microsserviço Report, cadastre:
        >
        > ```text
        > REPORT_CLIENT_ID
        > TENANT_ID
        > SUBSCRIPTION_ID
        > ```
        >
        > Essa etapa é necessária para que o deploy automatizado via GitHub Actions consiga autenticar na Azure usando OIDC.

    6. Exemplo de execução/gatilho da Function
        
        ```bash
        curl -X POST \
            -H "Content-Type: application/json" \
            -H "x-functions-key: $(az functionapp keys list \
                --name "$FUNCTION_REPORT_NAME" \
                --resource-group "$RG_NAME" \
                --query "masterKey" \
                --output tsv)" \
            -d '{"input": ""}' \
            "https://${FUNCTION_REPORT_NAME}.azurewebsites.net/admin/functions/func-feedback-report"
        ```

    > **Importante:** após configurar as credenciais e os secrets de cada repositório, é necessário disparar um build/deploy para que as aplicações sejam publicadas na Azure.
    >
    > Isso pode ser feito executando a GitHub Action correspondente em cada repositório:
    >
    > ```text
    > az-func-feedback-login
    > az-func-feedback-core
    > az-func-feedback-report
    > ```
    >
    > Sem essa etapa, a infraestrutura estará criada, mas o código da aplicação ainda não terá sido implantado nas Function Apps.


18. Limpeza

    > A limpeza manual é opcional. Os arquivos temporários gerados pelo script já estão listados no `.gitignore` para evitar commit acidental.
    >
    > Caso esteja usando o script automatizado, também é possível habilitar a limpeza automática definindo:
    >
    > ```bash
    > RUN_CLEANUP="true"
    > ```

    ```bash
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
    ```
    