#!/bin/bash

# ============================================
# VariPhi LMS - Production Deployment (GKE)
# ============================================
# This script builds, pushes, and deploys the LMS application to Google Kubernetes Engine
# Usage: ./run-production.sh

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="variphi"
CLUSTER_NAME="gke-prod-asia-south1"
REGION="asia-south1"
NAMESPACE="lms"
IMAGE_REPO="asia-south1-docker.pkg.dev/variphi/vgiskill/lms-app"
IMAGE_TAG="latest"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"
HELM_CHART_PATH="./helm-chart/lms-app"
RELEASE_NAME="lms"

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}🚀 VariPhi LMS - Production Deployment${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# Step 1: Check prerequisites
echo -e "${YELLOW}Step 1: Checking prerequisites...${NC}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    exit 1
fi
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker Desktop is not running!${NC}"
    echo "Please start Docker Desktop and run this script again."
    exit 1
fi
echo -e "${GREEN}   ✅ Docker is installed and running${NC}"

# Check gcloud
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}❌ Google Cloud SDK (gcloud) is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}   ✅ gcloud is installed${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}   ✅ kubectl is installed${NC}"

# Check Helm
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Helm is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}   ✅ Helm is installed${NC}"
echo ""

# Step 2: Verify authentication
echo -e "${YELLOW}Step 2: Verifying Google Cloud authentication...${NC}"
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo -e "${RED}❌ Not authenticated with Google Cloud${NC}"
    echo "Please run: gcloud auth login"
    exit 1
fi
ACTIVE_ACCOUNT=$(gcloud config get-value account)
echo -e "${GREEN}   ✅ Authenticated as: ${ACTIVE_ACCOUNT}${NC}"

# Set project
gcloud config set project ${PROJECT_ID} > /dev/null 2>&1
echo -e "${GREEN}   ✅ Project set to: ${PROJECT_ID}${NC}"
echo ""

# Step 3: Configure Docker for Artifact Registry
echo -e "${YELLOW}Step 3: Configuring Docker for Artifact Registry...${NC}"
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet
echo -e "${GREEN}   ✅ Docker configured${NC}"
echo ""

# Step 4: Build Docker image
echo -e "${YELLOW}Step 4: Building Docker image...${NC}"
echo -e "${BLUE}   Image: ${IMAGE_NAME}${NC}"
echo -e "${BLUE}   Platform: linux/amd64${NC}"
echo -e "${BLUE}   This may take 10-15 minutes...${NC}"
echo ""

docker build --platform linux/amd64 -t ${IMAGE_NAME} .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ✅ Docker image built successfully${NC}"
else
    echo -e "${RED}   ❌ Docker build failed${NC}"
    exit 1
fi
echo ""

# Step 5: Push image to registry
echo -e "${YELLOW}Step 5: Pushing image to Artifact Registry...${NC}"
echo -e "${BLUE}   This may take a few minutes...${NC}"
echo ""

docker push ${IMAGE_NAME}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ✅ Image pushed successfully${NC}"
else
    echo -e "${RED}   ❌ Image push failed${NC}"
    exit 1
fi
echo ""

# Step 6: Connect to GKE cluster
echo -e "${YELLOW}Step 6: Connecting to GKE cluster...${NC}"
gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ✅ Connected to cluster: ${CLUSTER_NAME}${NC}"
else
    echo -e "${RED}   ❌ Failed to connect to cluster${NC}"
    exit 1
fi
echo ""

# Step 7: Create namespace if it doesn't exist
echo -e "${YELLOW}Step 7: Ensuring namespace exists...${NC}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
echo -e "${GREEN}   ✅ Namespace ready: ${NAMESPACE}${NC}"
echo ""

# Step 8: Deploy with Helm
echo -e "${YELLOW}Step 8: Deploying with Helm...${NC}"
echo -e "${BLUE}   Chart: ${HELM_CHART_PATH}${NC}"
echo -e "${BLUE}   Release: ${RELEASE_NAME}${NC}"
echo ""

helm upgrade --install ${RELEASE_NAME} ${HELM_CHART_PATH} \
    --namespace ${NAMESPACE} \
    --wait \
    --timeout 10m \
    --set image.repository=${IMAGE_REPO} \
    --set image.tag=${IMAGE_TAG} \
    --set image.pullPolicy=Always

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ✅ Helm deployment complete${NC}"
else
    echo -e "${RED}   ❌ Helm deployment failed${NC}"
    exit 1
fi
echo ""

# Step 9: Wait for pods to be ready
echo -e "${YELLOW}Step 9: Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=lms-app \
    -n ${NAMESPACE} \
    --timeout=5m || echo -e "${YELLOW}   ⚠️  Some pods may still be starting...${NC}"
echo ""

# Step 10: Show deployment status
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}📊 Deployment Status${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

echo -e "${GREEN}📦 Pods:${NC}"
kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=lms-app -o wide
echo ""

echo -e "${GREEN}🔌 Services:${NC}"
kubectl get svc -n ${NAMESPACE} -l app.kubernetes.io/name=lms-app
echo ""

echo -e "${GREEN}🌐 Ingress:${NC}"
kubectl get ingress -n ${NAMESPACE} -l app.kubernetes.io/name=lms-app
echo ""

# Step 11: Get External IP
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}🌍 External Access${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

EXTERNAL_IP=$(kubectl get ingress -n ${NAMESPACE} -l app.kubernetes.io/name=lms-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$EXTERNAL_IP" ]; then
    echo -e "${YELLOW}⏳ External IP is still being provisioned...${NC}"
    echo ""
    echo "Run this command to check later:"
    echo -e "  ${BLUE}kubectl get ingress -n ${NAMESPACE} -l app.kubernetes.io/name=lms-app${NC}"
else
    echo -e "${GREEN}✅ External IP: ${EXTERNAL_IP}${NC}"
    echo ""
    echo -e "${YELLOW}🌐 Your application should be accessible at:${NC}"
    echo -e "   ${BLUE}https://vgiskill.ai${NC}"
fi
echo ""

# Step 12: Final summary
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}✅ Production Deployment Complete!${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""
echo -e "${YELLOW}📋 Useful Commands:${NC}"
echo -e "   View pods:        ${BLUE}kubectl get pods -n ${NAMESPACE}${NC}"
echo -e "   View logs:        ${BLUE}kubectl logs -f -n ${NAMESPACE} -l app.kubernetes.io/name=lms-app${NC}"
echo -e "   Check ingress:    ${BLUE}kubectl get ingress -n ${NAMESPACE}${NC}"
echo -e "   Restart pods:     ${BLUE}kubectl delete pod -n ${NAMESPACE} -l app.kubernetes.io/name=lms-app${NC}"
echo -e "   Helm status:     ${BLUE}helm status ${RELEASE_NAME} -n ${NAMESPACE}${NC}"
echo -e "   Helm upgrade:    ${BLUE}helm upgrade ${RELEASE_NAME} ${HELM_CHART_PATH} -n ${NAMESPACE}${NC}"
echo ""
echo -e "${YELLOW}🔧 Troubleshooting:${NC}"
echo -e "   If pods are not ready, check logs:"
echo -e "   ${BLUE}kubectl describe pod -n ${NAMESPACE} -l app.kubernetes.io/name=lms-app${NC}"
echo ""

