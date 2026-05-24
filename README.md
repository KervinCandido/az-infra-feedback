# FIAP Tech Challenge - Fase 04 (Feedback Platform)

Este projeto atua como repositório **centralizador** e de infraestrutura de todos os projetos que compõem a plataforma de Feedback da Fase 04 do FIAP Tech Challenge. Aqui você encontrará os detalhes de arquitetura, relacionamento entre os microsserviços e a automação de provisionamento de nuvem.

## 🏗 Arquitetura da Solução

A solução adota uma arquitetura orientada a microsserviços serverless, baseada nativamente nos recursos da **Microsoft Azure**. O objetivo é garantir segurança, escalabilidade automática e baixo custo por meio do consumo sob demanda.

![Arquitetura de Infraestrutura](./docs/arquitetura/Feedback_Platform_Infrastructure-Arquitetura_de_Infraestrutura___Azure__IaC_.png)

A plataforma de feedback foi decomposta nos seguintes módulos:

### 1. ⚙️ Microsserviços (Azure Functions)

Toda a lógica de negócios e APIs operam no formato Serverless através de Functions, separadas por domínios:

- **[az-func-feedback-login](https://github.com/KervinCandido/az-func-feedback-login)**: Responsável pelo módulo de autenticação e autorização. Realiza a emissão de tokens JWT e verificação de identidades utilizando chaves RSA assimétricas.
- **[az-func-feedback-core](https://github.com/KervinCandido/az-func-feedback-core)**: Microsserviço principal onde residem as regras de negócio de captura e processamento dos feedbacks. Integra-se ao banco de dados (PostgreSQL) e envia notificações (Azure Communication Services).
- **[az-func-feedback-report](https://github.com/KervinCandido/az-func-feedback-report)**: Microsserviço assíncrono para geração e processamento de relatórios, persistindo os resultados em blobs (Azure Storage Account) sem impactar o processamento online.

### 2. ☁️ Infraestrutura e IaC (Este repositório)

O repositório atual (`az-infra-feedback`) hospeda a documentação de infraestrutura, os diagramas e a automação para construção do ambiente cloud.

Os recursos provisionados de nuvem incluem:
- **Rede e Segurança**: Virtual Network (VNet) com Subnets privadas isolando o banco de dados.
- **Key Vault**: Gerenciamento seguro e centralizado de segredos (Senhas, Strings de Conexão e Chaves JWT).
- **Banco de Dados**: Azure Database for PostgreSQL (Flexible Server).
- **Armazenamento**: Azure Storage Account.
- **Notificações**: Azure Communication Services e Azure Email Services para envio de alertas.
- **Monitoramento**: Azure Log Analytics Workspace e Application Insights atrelados às Functions para observabilidade completa.

*Guias:*
- [Passo a passo de Infraestrutura (CREATE-INFRA.md)](./docs/arquitetura/CREATE-INFRA.md)
- [Diagrama de Arquitetura (architecture.puml)](./docs/arquitetura/architecture.puml)
---

## 🚀 Como Provisionar a Infraestrutura

Para recriar ou atualizar o ambiente na Azure, basta utilizar os scripts bash disponíveis. Certifique-se de ter o `az cli` instalado e autenticado.

```bash
# 1. Autentique-se no Azure
az login

# 2. Acesse a pasta de scripts
cd scripts

# 3. Ajustar valores das variaveis no script
ADMIN_EMAIL="<ADMIN_EMAIL>"
DB_ADMIN_PASSWORD="<SenhaSegura>"

# 4. Execute a automação de provisionamento (IaC)
./create-infra.sh
```
> O detalhamento manual passo a passo de todos os comandos que o script executa está documentado em `docs/arquitetura/CREATE-INFRA.md`.

## 🔒 Segurança e Deploy Automatizado (CI/CD)

Todo o ecossistema de microsserviços utiliza **GitHub Actions** em conjunto com **Azure AD Federated Credentials (OIDC)**. Isso proporciona:
1. Deploys contínuos a cada mudança na branch `main` dos respectivos repositórios.
2. Nenhuma credencial de nuvem persistida no GitHub; os runners assumem uma identidade provisória de forma segura.
3. Todas as credenciais de banco, storage e chaves JWT residem exclusivamente no **Azure Key Vault**, tendo sua permissão de leitura restrita via _Role-Based Access Control (RBAC)_.
