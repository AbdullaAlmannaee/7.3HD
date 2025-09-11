## What this is
Node.js + Express service with `/health`. CI/CD via Jenkins:
Build → Test (JUnit) → SonarCloud → Security (npm audit/Trivy) →
Push image → Deploy (docker-compose) + health check → Release tag → Monitoring ping.
