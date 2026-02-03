# ECR - Container Registries

ECR repositories voor de 3 RAG microservices.

## Repositories

| Service | Poort | Beschrijving |
|---------|-------|--------------|
| `document-chunking` | 8000 | Splits documenten in chunks |
| `embeddings-engine` | 8001 | Genereert vector embeddings |
| `rag-query` | 8002 | Beantwoordt queries via RAG |

## Docker Build & Push

```bash
# 1. Login bij ECR
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com

# 2. Build & push (voorbeeld voor document-chunking)
cd ecr/document-chunking
docker build -t <ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/faro-rag/document-chunking:latest .
docker push <ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/faro-rag/document-chunking:latest
```

## Gebruik in EKS

### Image URL formaat
```
<ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/faro-rag/<service-name>:latest
```

### Kubernetes Deployment voorbeeld
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: document-chunking
  namespace: rag-services
spec:
  replicas: 2
  selector:
    matchLabels:
      app: document-chunking
  template:
    metadata:
      labels:
        app: document-chunking
    spec:
      containers:
      - name: document-chunking
        image: <ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/faro-rag/document-chunking:latest
        ports:
        - containerPort: 8000
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: document-chunking
  namespace: rag-services
spec:
  selector:
    app: document-chunking
  ports:
  - port: 8000
    targetPort: 8000
```

### EKS moet ECR kunnen pullen
De EKS nodes hebben een IAM role nodig met ECR pull rechten:
```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
    "ecr:BatchCheckLayerAvailability"
  ],
  "Resource": "arn:aws:ecr:eu-central-1:<ACCOUNT_ID>:repository/faro-rag/*"
}
```

Vervang `<ACCOUNT_ID>` met je AWS account ID.
