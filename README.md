# Hackday

# Setting up DigitalOcean
- Make an account
- `terraform logout` just to be safe
- Make an api key
- Make a new folder to store everything
- Make 3 folders, infrastructure, services, and build

# Terraform getting started
Make a `main.tf` inside the infrastructure folder
- Make a `main.tf`
- Set up the digital ocean [provider](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs)
<details>
    <summary>Need help?</summary>

```terraform
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Set the variable value in *.tfvars file
# or using -var="do_token=..." CLI option
variable "do_token" {
  default = "" # I set my token here, insecure but easier
}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.do_token
}
```
</details>

- Add a digital ocean [kubernetes cluster](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs/resources/kubernetes_cluster)
<details>
    <summary>Need help?</summary>

```terraform
resource "digitalocean_kubernetes_cluster" "cluster" {
  name   = "harry"
  region = "lon1"
  version = "1.29.1-do.0"

  node_pool {
    name       = "worker-pool"
    size       = "s-1vcpu-2gb"
    node_count = 1
  }
}
```
</details>

- Run `terraform init` to fetch the deps
- Run `terraform apply` to make the cluster
- We've now made a cluster in digital ocean, we now want to connect it to kubernetes
- Use the official kubernetes [provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)

<details>
    <summary>Need help?</summary>
    
```terraform
provider "kubernetes" {
  host = digitalocean_kubernetes_cluster.cluster.endpoint
  token   = digitalocean_kubernetes_cluster.cluster.kube_config[0].token
  cluster_ca_certificate = base64decode(
    digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate
  )
}
```
</details>

- Make a kubernetes [deployment](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment), use an nginx image for now
<details>
    <summary>Need help?</summary>

```terraform
resource "kubernetes_deployment" "deployment" {
  metadata {
    name = "nginx-example"
    labels = {
      app = "NginxExample"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "NginxExample"
      }
    }
    template {
      metadata {
        labels = {
          app = "NginxExample"
        }
      }
      spec {
        container {
          image = "nginx:latest"
          name  = "example"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}
```
</details>

- `terraform init` and `terraform apply` again
- It'll now be created, but we can't see it running yet
- Connect kubectl to the cluster

<details>
    <summary>Need help?</summary>

- https://docs.digitalocean.com/products/kubernetes/how-to/connect-to-cluster/
- `doctl kubernetes cluster kubeconfig save harry`, this will also change your current cluster
- `kubectl config get-contexts`
</details>

- If you're connected run these to check everything is up and running
- `kubectl get pods`
- `kubectl port-forward <pod-name> 3000:80`
- `kubectl describe deployment nginx-example`
- Now expose it to the internet using a [service](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service)
- https://www.baeldung.com/ops/kubernetes-service-types

<details>
    <summary>Need help?</summary>

```terraform
resource "kubernetes_service" "nginx-example" {
  metadata {
    name = "nginx-example"
  }
  spec {
    selector = {
      app = kubernetes_deployment.deployment.metadata[0].labels.app
    }
    port {
      port        = 8080
      target_port = 80
    }
    type = "LoadBalancer"
  }
}
```
</details>

- `kubectl get service` will list it's external ip mine was `206.189.246.3`
- go to `http://206.189.246.3:8080/` and see your nginx
- This probably isn't the best way to get it actually exposed but is fine for now
- If you were doing this properly you'd use a load balancer from digital ocean I think
- If you comment these out and run `terraform apply` terraform will delete them for you

# Deploying our own app
- Make a new next project
- Put it in a `Dockerfile` and build it locally

<details>
    <summary>Need help?</summary>

- `yarn create next-app frontend`
- Make a file called `Dockerfile` in that folder
- The contents of the dockerfile will be complicated, I googled it and found one that worked 
```dockerfile
FROM node:18-alpine as base
RUN apk add --no-cache g++ make py3-pip libc6-compat
WORKDIR /app
COPY package*.json ./
COPY yarn.lock ./
EXPOSE 3000

FROM base as builder
WORKDIR /app
COPY . .
RUN yarn build


FROM base as production
WORKDIR /app

ENV NODE_ENV=production
RUN yarn install

RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001
USER nextjs


COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/public ./public

CMD yarn start
```
</details>

## Setting up a container registry
We've got the docker image locally but kubernetes can't access it.
We need to push the image to a container registry first.

- In terraform make a digital ocean container registry, we'll want it to be 'basic' because we need more than 1 repository

<details>
    <summary>Need help?</summary>

```terraform
resource "digitalocean_container_registry" "container_registry" {
  name                   = "harry"
  subscription_tier_slug = "basic"
}
```
</details>

- We need to tag our image and push to it

<details>
    <summary>Need help?</summary>

- We now need to authenticate our local docker to be allowed to push images to it
- `docker login registry.digitalocean.com` email is you email, password is the api token
- Now build it with a tag, we'll need the `--platform=linux/amd64` bit because it's going to run on a linus machine not an m1 mac
- `docker build --platform=linux/amd64 -t registry.digitalocean.com/harry/frontend .`
- Now push it up
- `docker push registry.digitalocean.com/harry/frontend`
- You'll be able to see the image in the digitalocean frontend
</details>

- Now use the image in kubernetes
<details>
    <summary>Need help?</summary>

- The cluster also needs to be authenticated to fetch our docker image
- If you want to figure it out yourself see [this](https://stackoverflow.com/questions/32726923/pulling-images-from-private-registry-in-kubernetes)
- Remember to keep everything in terraform, no cheating!

</details>


<details>
    <summary>Still need help?</summary>

```terraform
resource "digitalocean_container_registry_docker_credentials" "container_registry_credentials" {
  registry_name = digitalocean_container_registry.container_registry.name
}

resource "kubernetes_secret" "docker_credentials" {
  metadata {
    name = "docker-credentials"
  }

  data = {
    ".dockerconfigjson" = digitalocean_container_registry_docker_credentials.container_registry_credentials.docker_credentials
  }

  type = "kubernetes.io/dockerconfigjson"
}
```
</details>

- Now copy the nginx deployment and service but use our image

<details>
    <summary>Need help?</summary>


```terraform
resource "kubernetes_deployment" "frontend" {
  metadata {
    name = "frontend"
    labels = {
      app = "frontend"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "frontend"
      }
    }
    template {
      metadata {
        labels = {
          app = "frontend"
        }
      }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.docker_credentials.metadata[0].name
        }

        container {
          image = "${digitalocean_container_registry.container_registry.endpoint}/frontend"
          name  = "example"

          port {
            container_port = 3000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend" {
  metadata {
    name = "frontend"
  }
  spec {
    selector = {
      app = kubernetes_deployment.frontend.metadata[0].labels.app
    }
    port {
      port        = 3000
      target_port = 3000
    }
    type = "LoadBalancer"
  }
}
```

> We could hard code the image name, but I want to reuse as many variables as possible
</details>

- You should be able to visit you site

# Connecting to another service
- Make a http service
- Put it in a Dockerfile, build and push it

<details>
    <summary>Need help?</summary>


- `go mod init github.com/harryfpayne/babys-first-infra/services/backend`
- make a `main.go` with a simple "Hello, World!" http server
```go
package main

import "net/http"

func main() {
	http.HandleFunc("/", handler)

	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		panic(err)
	}
}

func handler(w http.ResponseWriter, r *http.Request) {
	w.Write([]byte("Hello, World!"))
}
```
- Put it in a docker image
```dockerfile
FROM golang

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY *.go ./

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -o /main

EXPOSE 8080

# Run
CMD ["/main"]
```
- Build it `docker build --platform=linux/amd64 -t registry.digitalocean.com/harry/backend .`
- Push it `docker push registry.digitalocean.com/harry/backend`
</details>

- Make a deployment and a service for this backend
- We're not going to expose this backend to the public, instead we'll use [Nextjs api routes](https://nextjs.org/docs/pages/building-your-application/routing/api-routes) to talk to it

<details>
    <summary>Need help?</summary>

```terraform
resource "kubernetes_deployment" "backend" {
  metadata {
    name = "backend"
    labels = {
      app = "backend"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "backend"
      }
    }
    template {
      metadata {
        labels = {
          app = "backend"
        }
      }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.docker_credentials.metadata[0].name
        }

        container {
          image = "${digitalocean_container_registry.container_registry.endpoint}/backend"
          name  = "example"

          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "backend" {
  metadata {
    name = "backend"
  }
  spec {
    selector = {
      app = kubernetes_deployment.backend.metadata[0].labels.app
    }
    port {
      port        = 80
      target_port = 8080
    }
    type = "ClusterIP"
  }
}
```

> We're using a ClusterIP for the service so that it doesn't get a public ip address.
> Read the types of service article from above
</details>

- Make an api route in the frontend and talk to it using its cluster dns name

<details>
    <summary>Need help?</summary>

- https://yuminlee2.medium.com/kubernetes-dns-bdca7b7cb868#:~:text=In%20Kubernetes%2C%20DNS%20names%20are%20assigned%20to%20Pods%20and%20Services,can%20be%20customized%20if%20required.
- I checked the DNS name of the backend by:
    - `kubectl exec -it <podname> sh` to 'ssh' into it
    - `nslookup backend` gives dns entries containing `backend` for us
    - the DNS entry is`backend.default.svc.cluster.local`
- We'll pass this as an environment variable to the frontend
```terraform
resource "kubernetes_deployment" "frontend" {
  metadata {
    name = "frontend"
    labels = {
      app = "frontend"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "frontend"
      }
    }
    template {
      metadata {
        labels = {
          app = "frontend"
        }
      }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.docker_credentials.metadata[0].name
        }

        container {
          image = "${digitalocean_container_registry.container_registry.endpoint}/frontend"
          name  = "example"

          port {
            container_port = 3000
          }

          env {
            name = "API_URL"
            value = "backend.default.svc.cluster.local"
          }
        }
      }
    }
  }
}
```
- I'll now add an api route to talk to the backend, I'm modifying the default `hello.ts` one
```typescript
import type { NextApiRequest, NextApiResponse } from "next";

export default async function handler(
        req: NextApiRequest,
        res: NextApiResponse<any>,
) {
  const url = process.env.API_URL
  console.log(url)
  const response = await fetch(`http://${url}`)
          .then(r => r.text())
          .catch(e => console.error(e))
  res.status(200).json({ response: response });
}
```
</details>

- Rebuild the docker image for the frontend and push it

<details>
    <summary>Need help?</summary>

- We didn't tag a specific version of the docker image before so the frontend probably won't change
- Add an image pull policy so kube always fetches the latest image
```terraform
image_pull_policy = "Always"
```
</details>

- We're now able to communicate with the backend via our website!

# Using helm
The deployments and services are very similar it would be nice if we could reuse them.
We could use a terraform module but for this case we'll use a helm chart

- As an example add an nginx helm chart to our terraform

<details>
    <summary>Need help?</summary>


```terraform
provider "helm" {
  kubernetes {
    host                   = digitalocean_kubernetes_cluster.cluster.endpoint
    token                  = digitalocean_kubernetes_cluster.cluster.kube_config[0].token
    cluster_ca_certificate = base64decode(
      digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate
    )
  }
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress-controller"

  repository = "https://charts.bitnami.com/bitnami"
  chart      = "nginx-ingress-controller"

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }
}
```
</details>

- It'll give the load balancer a public ip, you can go to that to check its working
- By installing that helm chart we've made a collection of kubernetes resources instead of having to list each of them
- There's 2 deployments, 2 services, and probably some other stuff
- You can also `helm ls` to see the helm charts currently installed

## Making our own helm chart
- In the `build` folder make a new helm chart `helm create microservice-deployment`
- You can do `helm create --help` to understand the helm folder structure
- It makes a load files by default, we don't need most of them
- Strip out everything we don't need, make it a helm chart we can reuse for both frontend and backend

<details>
    <summary>Need help?</summary>

I didn't actually do this bit, but I did most of it.
This is only valid for the frontend but can quite easily be changed to also work for the backend.

#### deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.appName }}
  labels:
    app: {{ .Values.appName }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      {{- if .Values.imagePullSecretsName }}
      imagePullSecrets:
        name: {{ .Values.imagePullSecretsName }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
```
#### service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}
  labels:
    app: {{ .Values.appName }}
spec:
  type: "LoadBalancer"
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
      name: http
  selector:
    app: {{ .Values.appName }}
```
#### values.yaml
```yaml
replicaCount: 1

image:
  repository: nginx
  tag: latest

imagePullSecrets: []

service:
  port: 80
  targetPort: 3000

appName: frontend
```
- You can run `helm lint` to check it's valid
</details>

- Delete the frontend / backend deployments and services in terraform
- Change the values in `values.yaml` to be specific for the frontend app
- Run `helm install frontend .` to get the frontend back
- Delete it using `helm uninstall frontend`
- Using the helm chart deploy both the frontend and backend from terraform

<details>
    <summary>Need help?</summary>

Here's my code for the frontend, you'll likely need to set extra different values

```terraform
resource "helm_release" "frontend" {
  name  = "frontend"
  chart = "${path.module}/../build/microservice-deployment"

  set {
    name  = "image.repository"
    value = "${digitalocean_container_registry.container_registry.endpoint}/frontend"
  }
  set {
    name  = "image.tag"
    value = "latest"
  }

  set {
    name = "imagePullSecretsName"
    value = kubernetes_secret.docker_credentials.metadata[0].name
  }

  set {
    name  = "service.port"
    value = "3000"
  }
  set {
    name  = "service.targetPort"
    value = "3000"
  }

  set {
      name  = "appName"
      value = "frontend"
  }
}
```
</details>


# Next steps
- Use helm to install postgres and connect to is with your backend
- Or deploy a managed database on digital ocean (using terraform)
- Add a domain name to your digital ocean account and connect your frontend service to it
- Deploy multiple backend services and communicate between them
- Automate deployments by versioning the docker images and using github actions
- Setup PubSub to send messages between services
- Make a protobuf file, generate the types, and use rpc to communicate between services


# Cleaning up
You'll be charged by digital ocean if you leave this running.

Run `terraform destroy` to delete everything


