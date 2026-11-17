"""social_preview.py: draws docs/media/social-preview.png (1280x640), the card GitHub/LinkedIn show for the repo link.

Generated from code so the text stays in sync with the project. Needs Pillow and the `diagrams` package
(only for its bundled tool logos):
    .venv/bin/pip install pillow diagrams
    .venv/bin/python docs/diagrams/social_preview.py          # run from the repo root
Upload the result in GitHub: Settings → General → Social preview.
"""
import os

import diagrams
from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 640
BG, FG, MUTED, ACCENT = (15, 23, 42), (248, 250, 252), (148, 163, 184), (56, 189, 248)
ICONS = os.path.join(os.path.dirname(diagrams.__file__), "..", "resources")


def font(size, bold=False):
    # Helvetica Neue ships with macOS; index 1 in the collection is the bold face.
    return ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", size, index=1 if bold else 0)


img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

# A thin accent bar on the left edge.
d.rectangle([0, 0, 12, H], fill=ACCENT)

x = 80
d.text((x, 70), "eks-delivery-pipeline", font=font(64, bold=True), fill=FG)
d.text((x, 160), "Commit  ›  tested  ›  containerized  ›  deployed to AWS EKS", font=font(32), fill=ACCENT)

bullets = [
    "Zero-downtime rolling updates (0 failed requests measured)",
    "Automatic rollback when a release never becomes Ready",
    "100% Terraform: VPC · EKS on Graviton Spot · ECR · least-privilege IAM",
    "Prometheus · Grafana · Alertmanager › Slack on user-facing symptoms",
]
y = 245
for b in bullets:
    d.ellipse([x, y + 13, x + 10, y + 23], fill=ACCENT)
    d.text((x + 26, y), b, font=font(27), fill=FG)
    y += 50

# Tool logos along the bottom.
logos = [
    "aws/compute/elastic-kubernetes-service.png", "onprem/iac/terraform.png", "onprem/ci/jenkins.png",
    "onprem/container/docker.png", "k8s/k8s.png", "onprem/monitoring/prometheus.png",
    "onprem/monitoring/grafana.png",
]
lx, size = x, 64
for rel in logos:
    path = os.path.join(ICONS, rel)
    if not os.path.exists(path):
        continue
    logo = Image.open(path).convert("RGBA")
    logo.thumbnail((size, size))
    img.paste(logo, (lx, 500), logo)
    lx += size + 28

d.text((W - 80, 590), "≈ $0.14/hour · fully destroyable", font=font(24), fill=MUTED, anchor="rs")

img.save("docs/media/social-preview.png", optimize=True)
print("wrote docs/media/social-preview.png")
