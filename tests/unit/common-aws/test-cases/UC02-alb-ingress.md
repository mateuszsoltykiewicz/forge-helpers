# UC02: ALB Ingress with AWS Load Balancer Controller

## Overview
Tests Application Load Balancer (ALB) provisioning via Kubernetes Ingress using the AWS Load Balancer Controller. This controller watches Ingress resources and automatically creates/configures ALBs in AWS.

## AWS Load Balancer Controller
The AWS Load Balancer Controller manages AWS Elastic Load Balancers for Kubernetes:
- **ALB**: Application Load Balancer (Layer 7 - HTTP/HTTPS)
- **NLB**: Network Load Balancer (Layer 4 - TCP/UDP)
- **TargetGroupBinding**: Direct pod-to-target-group mapping

## Use Cases
- **Public APIs**: Internet-facing HTTP/HTTPS endpoints
- **Microservices**: Path-based routing to multiple services
- **SSL/TLS Termination**: HTTPS with ACM certificates
- **WAF Integration**: AWS WAF rules on ALB
- **Host-Based Routing**: Multiple domains on single ALB
- **Cost Optimization**: Single ALB for multiple services

## Prerequisites
- AWS EKS cluster
- AWS Load Balancer Controller installed (v2.4+)
- VPC subnets tagged for ALB discovery:
  - Public subnets: `kubernetes.io/role/elb=1`
  - Private subnets: `kubernetes.io/role/internal-elb=1`
- IAM policy for Load Balancer Controller (IRSA)

## Test Objectives
1. Deploy application with Service (ClusterIP)
2. Create Ingress with ALB annotations
3. Verify ALB created in AWS console
4. Check target group health checks
5. Test HTTP access via ALB DNS name
6. Validate path-based routing

## ALB Annotations
```yaml
alb.ingress.kubernetes.io/scheme: internet-facing | internal
alb.ingress.kubernetes.io/target-type: ip | instance
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/id
alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS-1-2-2017-01
alb.ingress.kubernetes.io/healthcheck-path: /health
alb.ingress.kubernetes.io/tags: key1=value1,key2=value2
```

## References
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [ALB Ingress Annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)
- [Subnet Discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/subnet_discovery/)
