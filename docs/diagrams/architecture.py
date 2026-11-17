"""architecture.py: draws docs/media/architecture.png, the AWS architecture diagram in the README.

Diagrams as code: the picture is generated from this file, so it can be reviewed in a pull request and
regenerated whenever the infrastructure changes. Uses the open-source `diagrams` library (needs Graphviz):

    python3 -m venv .venv && .venv/bin/pip install diagrams     # once
    brew install graphviz                                        # once (provides the `dot` renderer)
    .venv/bin/python docs/diagrams/architecture.py               # run from the repo root
"""
from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EKS, ECR
from diagrams.aws.network import InternetGateway
from diagrams.aws.security import IAM
from diagrams.aws.storage import S3
from diagrams.k8s.compute import Pod
from diagrams.onprem.ci import Jenkins
from diagrams.onprem.iac import Terraform
from diagrams.onprem.monitoring import Grafana, Prometheus
from diagrams.onprem.vcs import Github
from diagrams.saas.chat import Slack

# Layout and font settings: left-to-right flow, generous spacing so labels don't overlap.
graph_attr = {"fontsize": "22", "pad": "0.4", "nodesep": "0.7", "ranksep": "1.0", "fontname": "Helvetica"}
node_attr = {"fontsize": "13", "fontname": "Helvetica"}

with Diagram(
    "eks-delivery-pipeline",
    filename="docs/media/architecture",  # writes docs/media/architecture.png
    outformat="png",
    show=False,  # don't try to open an image viewer
    direction="LR",
    graph_attr=graph_attr,
    node_attr=node_attr,
):
    github = Github("GitHub\n(source)")

    with Cluster("Developer laptop"):
        jenkins = Jenkins("Jenkins\ntest · build · push · deploy\nauto-rollback")
        terraform = Terraform("Terraform")

    with Cluster("AWS · ap-south-1"):
        ecr = ECR("ECR hello-app\nimmutable SHA tags")
        state = S3("S3 state\nversioned · encrypted\nnative locking")
        iam = IAM("IAM jenkins-ci\n1 repo · 1 namespace")

        with Cluster("VPC 10.0.0.0/16 · 2 public subnets · no NAT"):
            igw = InternetGateway("Internet\ngateway")
            eks = EKS("EKS control plane\nstandard support")

            with Cluster("Graviton Spot node group (t4g)"):
                nodes = [EC2("node AZ-a"), EC2("node AZ-b")]

                with Cluster("namespace app"):
                    pods = [Pod("hello-app"), Pod("hello-app")]

                with Cluster("namespace monitoring"):
                    prom = Prometheus("Prometheus")
                    graf = Grafana("Grafana")

    slack = Slack("Slack #alerts")

    # The delivery path (the bold edges are the main story).
    github >> Edge(label="poll every 2 min", style="bold") >> jenkins
    jenkins >> Edge(label="docker push", style="bold") >> ecr
    jenkins >> Edge(label="kubectl apply", style="bold") >> eks
    jenkins - Edge(style="dotted", label="authenticates as") - iam
    eks >> nodes
    nodes[0] >> pods[0]
    nodes[1] >> pods[1]
    ecr >> Edge(label="pull only", style="dashed") >> nodes[1]
    igw - Edge(style="dotted") - nodes[0]

    # Infrastructure as code.
    terraform >> Edge(label="creates", style="dashed", color="gray") >> eks
    terraform >> Edge(label="state", style="dashed", color="gray") >> state

    # Observability.
    pods >> Edge(label="/metrics", color="darkorange") >> prom
    prom >> Edge(color="darkorange") >> graf
    prom >> Edge(label="alerts", color="firebrick") >> slack
