# Tech Challenge FIAP Fase 4

## Projeto

**Tech Challenge FIAP — Fase 4**  
**Curso:** Pós-Graduação em Arquitetura e Desenvolvimento em Java  
**Serviços:** `az-func-feedback-login`, `az-func-feedback-core` e `az-func-feedback-report`     
**Tema:** Plataforma serverless para recebimento, classificação, persistência e notificação de feedbacks educacionais.

## Equipe

| Nome | RM | E-mail |
|---|---:|---|
| Alexandre Belisário Duarte Leite de Andrade | RM367163 | alexbdla@gmail.com |
| Kervin Sama Candido da Silva | RM367345 | kervincandido@gmail.com |

## Links do projeto

| Item | Link |
|---|---|
| **[az-infra-feedback](https://github.com/KervinCandido/az-infra-feedback)** | https://github.com/KervinCandido/az-infra-feedback |
| **[az-func-feedback-login](https://github.com/KervinCandido/az-func-feedback-login)** | https://github.com/KervinCandido/az-func-feedback-login |
| **[az-func-feedback-core](https://github.com/KervinCandido/az-func-feedback-core)** | https://github.com/KervinCandido/az-func-feedback-core |
| **[az-func-feedback-report](https://github.com/KervinCandido/az-func-feedback-report)** | https://github.com/KervinCandido/az-func-feedback-report |
| **[Vídeo de apresentação](https://www.youtube.com/)** | https://www.youtube.com/ **(Pendente)**| 
| **[Collection Postman](https://github.com/KervinCandido/az-infra-feedback/blob/main/collections/Feedback%20Platform.postman_collection.json)** | https://github.com/KervinCandido/az-infra-feedback/blob/main/collections/Feedback%20Platform.postman_collection.json |

## Arquitetura da Solução

A solução adota uma arquitetura orientada a microsserviços serverless, baseada nativamente nos recursos da **Microsoft Azure**. O objetivo é garantir segurança, escalabilidade automática e baixo custo por meio do consumo sob demanda.

![Arquitetura de Infraestrutura](../arquitetura/Feedback_Platform_Infrastructure-Arquitetura_de_Infraestrutura___Azure__IaC_.png)

### Microsserviços (Azure Functions)
Toda a lógica de negócios e APIs operam no formato Serverless através de Functions, separadas por domínios:

- **az-func-feedback-login**:
  Responsável pelo módulo de autenticação e autorização. Realiza a emissão de tokens JWT e verificação de identidades utilizando chaves RSA assimétricas.
- **az-func-feedback-core**:
  Microsserviço principal onde residem as regras de negócio de captura e processamento dos feedbacks. Integra-se ao banco de dados (PostgreSQL) e envia notificações (Azure Communication Services).
- **az-func-feedback-report**:
  Microsserviço assíncrono para geração e processamento de relatórios, persistindo os resultados em blobs (Azure Storage Account) e enviando o relatório para os administradores por e-mail via Azure Communication Services.

### Infraestrutura e IaC
A automação da infraestrutura cloud foi realizada utilizando repositório `az-infra-feedback`, que apresenta os diagramas e a automação para construção do ambiente cloud.

Os recursos provisionados de nuvem incluem:
- **Rede e Segurança**: Virtual Network (VNet) com Subnets privadas isolando o banco de dados.
- **Key Vault**: Gerenciamento seguro e centralizado de segredos (Senhas, Strings de Conexão e Chaves JWT).
- **Banco de Dados**: Azure Database for PostgreSQL (Flexible Server).
- **Armazenamento**: Azure Storage Account.
- **Notificações**: Azure Communication Services e Azure Email Services para envio de alertas.
- **Monitoramento**: Azure Log Analytics Workspace e Application Insights atrelados às Functions para observabilidade completa.
- **Computação**: Azure Functions (Planos de consumo para otimização de custos).

## Deploy Automatizado (CI/CD)

Toda a solução utiliza **GitHub Actions** em conjunto com **Azure AD Federated Credentials (OIDC)**. Isso proporciona:
1. Deploys contínuos a cada mudança na branch `main`.
2. Nenhuma credencial persistida no GitHub; os runners assumem uma identidade provisória de forma segura.
3. Todas as credenciais de banco, storage e chaves JWT residem exclusivamente no **Azure Key Vault**.

### Motivação do uso de CI/CD
Com o uso dessa solução, sempre que um integrante da equipe altera o repositório e envia as atualizações para a branch main, um processo de CI/CD é iniciado automaticamente. Isso realiza o build e o deploy dos serviços sem a necessidade de intervenção manual, garantindo que as alterações cheguem à produção de forma rápida e segura.