# GitHub Actions Workflows

## Beschikbare Workflows

### 🚀 Terraform Deploy (`terraform-deploy.yml`)
Deployt de volledige RAG-infrastructuur naar AWS.

**Trigger:** Handmatig via Actions tab
**Vereisten:**
- GitHub Secret: `DB_PASSWORD` (RDS database wachtwoord)
- AWS OIDC configuratie voor authenticatie

**Wat wordt gedeployd:**
- EKS cluster (v1.34) met nodegroups
- RDS PostgreSQL database met pgvector
- VPC met subnets (2 public, 2 private)
- S3 bucket voor documenten
- IAM roles en security groups

---

### 🗑️ Terraform Destroy (`terraform-destroy.yml`)
Verwijdert alle infrastructuur om kosten te stoppen.

**Trigger:** Handmatig via Actions tab
**Bevestiging vereist:** Type `DESTROY` bij uitvoeren

**Pre-Destroy Cleanup:**
- Leegt S3 bucket (alle versies)
- Verwijdert EKS nodegroups
- Ruimt Lambda ENIs op

**Let op:** Backend resources (S3 state bucket + DynamoDB tabel) worden NIET verwijderd.

---

## Terraform State Management

**Backend:**
- S3 Bucket: `faro-rag-terraform-state-894866952568`
- DynamoDB Tabel: `faro-rag-terraform-locks`
- Region: `eu-central-1`

State wordt automatisch vergrendeld tijdens workflows om conflicten te voorkomen.

---

## AWS Authenticatie

Workflows gebruiken OIDC (OpenID Connect) - geen static credentials nodig.

**IAM Role:** `github-actions-terraform-role`
**OIDC Provider:** `token.actions.githubusercontent.com`

---

## Kosten

- **Actieve infrastructuur:** ~€100-130/maand
- **EKS v1.34:** Standard support (goedkoper dan v1.31 extended)
- **Tip:** Run destroy workflow als infrastructuur niet gebruikt wordt
