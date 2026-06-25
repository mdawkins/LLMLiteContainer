Since you are running a RHEL 9 box with direct access to Amazon Bedrock, the enterprise standard for this exact setup is **LiteLLM Proxy**. AWS explicitly utilizes LiteLLM to implement usage limits, multi-user authentication, and centralized governance for tools like Claude Code and IDE extensions. \[1, 2, 3, 4\]

LiteLLM acts as a central proxy that translates an incoming standard OpenAI/Anthropic format into Amazon Bedrock API calls natively, allowing you to establish user keys, track token usage, and enforce rate throttling. \[2, 5\]

---

## Step 1: Deploy LiteLLM using Podman on RHEL 9

RHEL 9 ships natively with `podman` rather than Docker. You will also need a lightweight PostgreSQL container to handle the persistent state of user tokens, authentication, and throttling balances. \[1, 6\]

1. Create an isolated internal container network:

```shell
podman network create llm-net
```

2. Spin up the PostgreSQL database container:

```shell
podman run -d --name litellm-db \
  --network llm-net \
  -e POSTGRES_DB=litellm \
  -e POSTGRES_USER=proxy_admin \
  -e POSTGRES_PASSWORD=YourSecurePassword Here \
  postgres:16
```

3. Create your base configuration file (`config.yaml`) to map to Amazon Bedrock models:

```
model_list:
  - model_name: claude-3-5-sonnet
    litellm_params:
      model: bedrock/anthropic.claude-3-5-sonnet-20241022-v2:0 # Example model ID
```

4. Run the LiteLLM Proxy container, passing your AWS IAM Bedrock permissions (or local AWS profile/credentials) into the runtime environment:

```shell
podman run -d --name litellm-proxy \
  --network llm-net \
  -p 4000:4000 \
  -v ./config.yaml:/app/config.yaml \
  -e DATABASE_URL="postgresql://proxy_admin:YourSecurePasswordHere@litellm-db:5432/litellm" \
  -e AWS_ACCESS_KEY_ID="your_key" \
  -e AWS_SECRET_ACCESS_KEY="your_secret" \
  -e AWS_REGION="us-east-1" \
  ghcr.io/berriai/litellm:main-latest --config /app/config.yaml
```

5. \[7, 8\]

---

## Step 2: Establish User Authentication and Throttling Limits

Once LiteLLM is running, use its Management API (or the included UI via port 4000\) to generate unique authentication tokens for your engineering teams.

You can set strict **TPM** (Tokens Per Minute), **RPM** (Requests Per Minute), or total dollar-based budget caps: \[9\]

```shell
curl -X POST 'http://localhost:4000/key/generate' \
  -H 'Authorization: Bearer sk-your-master-proxy-key' \
  -H 'Content-Type: application/json' \
  -d '{
    "key_alias": "developer_team_alpha",
    "max_budget": 50.00,
    "budget_duration": "30d",
    "tpm_limit": 40000,
    "rpm_limit": 200
  }'
```

This returns a dedicated proxy token (`sk-...`) configured with automated rate limits that drop traffic when thresholds are crossed. \[1, 10\]

---

## Step 3: Connect User Platforms to the Proxy

Because LiteLLM exposes endpoints formatted identically to direct OpenAI/Anthropic APIs, it interfaces seamlessly with all your target client platforms. \[2, 5\]

## **1\. Claude Code CLI \[11\]**

To point Claude Code away from Anthropic infrastructure and into your RHEL 9 router, set the following target variables inside the user's local terminal profile:

```shell
export ANTHROPIC_BASE_URL="http://your-rhel-box-ip:4000"
export ANTHROPIC_API_KEY="sk-generated-user-token"
```

## **2\. VS Code & Visual Studio**

For users leveraging IDE components (like Claude Dev, Roo Code, or Continue extensions):

*   
* **Provider**: Select **OpenAI-Compatible** or **Anthropic** (depending on how you structured the target endpoint aliases in `config.yaml`).  
* **Base URL**: Provide `http://your-rhel-box-ip:4000/v1` or `http://your-rhel-box-ip:4000/v1/chat/completions`.  
* **API Key**: Input the individual user key generated in Step 2\. \[12\]  
* 

## **3\. Claude Desktop / Cowork \[13\]**

For the standard desktop application workflow to connect safely via a third-party platform interface, modify the local deployment configurations: \[14, 15\]

*   
* **Windows path**: `%APPDATA%\Claude\claude_desktop_config.json`  
* **macOS path**: `~/Library/Application Support/Claude/claude_desktop_config.json` \[16\]  
* 

Populate the configuration file to point directly to your RHEL proxy:

```json
{
  "mcpServers": {},
  "inference": {
    "provider": "openai-compatible",
    "baseURL": "http://your-rhel-box-ip:4000/v1",
    "apiKey": "sk-generated-user-token"
  }
}
```

Would you like assistance in **setting up an Nginx reverse proxy** on your RHEL 9 box to secure user traffic via TLS/HTTPS, or do you need help **structuring the specific model configurations** in the `config.yaml` file for your Bedrock endpoints? \[5\]

To secure your router traffic with TLS, we will deploy an Nginx container inside Podman. It will terminate HTTPS traffic on port 443 and proxy it securely over the internal llm-net network to LiteLLM. \[[1](https://oneuptime.com/blog/post/2026-03-18-run-nginx-podman-container/view), [2](https://coder.com/blog/deploying-coder-with-docker-and-https), [3](https://www.digitalocean.com/community/tutorials/how-to-scale-and-secure-a-django-application-with-docker-nginx-and-let-s-encrypt)\]

Since we are adding Nginx, you should **remove the \-p 4000:4000 port mapping from your LiteLLM startup command** so that the unencrypted backend is entirely isolated from the network.

Step 1: Prepare the Certificates and Nginx Configuration \[[1](https://kiljan.org/2021/04/11/integrating-a-signal-tls-proxy-in-an-existing-site-using-haproxy/), [2](https://kgateway.dev/docs/envoy/2.0.x/setup/listeners/tls-passthrough/), [3](https://www.thecodeship.com/web-development/guide-implementing-free-ssl-certificate-nginx-lets-encrypt/)\]

Create a dedicated folder structure on your RHEL 9 box to keep configuration separate from data.

1. **Create directories:**  
   bash

```
mkdir -p /etc/nginx-proxy/certs
```

2.   
   Use code with caution.  
3. **Place your TLS Certificates:**  
   Drop your domain’s valid SSL certificates into /etc/nginx-proxy/certs/. If you are testing locally, you can generate a self-signed certificate:  
   bash

```
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx-proxy/certs/proxy.key \
  -out /etc/nginx-proxy/certs/proxy.crt \
  -subj "/CN=your-rhel-hostname-or-ip"
```

4.   
   Use code with caution.  
5. **Create the Nginx Configuration (/etc/nginx-proxy/nginx.conf):**  
   nginx

```
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Maximize payload capability for large text/code inputs
    client_max_body_size 50M;

    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name _;

        ssl_certificate /etc/nginx/certs/proxy.crt;
        ssl_certificate_key /etc/nginx/certs/proxy.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        location / {
            # Pass traffic to LiteLLM container name on the internal podman network
            proxy_pass http://litellm-proxy:4000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Prevent proxy buffering for real-time token streaming
            proxy_buffering off;
            proxy_read_timeout 600s;
        }
    }
}
```

6.   
   Use code with caution.  
    \[[1](https://deployn.de/en/blog/ssl-pfx-pem/), [2](https://cloudinfrastructureservices.co.uk/nginx-ssl-tls-configuration-how-to-enable-https-on-your-nginx-server/), [3](https://www.digitalocean.com/community/tutorials/how-to-create-a-self-signed-ssl-certificate-for-nginx-in-ubuntu-18-04), [4](https://www.itix.fr/blog/nginx-with-tls-on-openwrt/), [5](https://clouddocs.f5.com/training/community/nginx/html/class5/module1/module1.html)\]

Step 2: Spin Up the Nginx Container \[[1](https://tcude.net/hosting-internal-sites-with-nginx/)\]

Run the container on your existing llm-net network.

Because RHEL 9 enforces strict SElinux policies, you must append :Z to your volume mounts. This flags Podman to automatically relabel the files so the container has permission to read your configuration and certificates.

bash

```
podman run -d --name nginx-tls-proxy \
  --network llm-net \
  -p 80:80 \
  -p 443:443 \
  -v /etc/nginx-proxy/nginx.conf:/etc/nginx/nginx.conf:Z \
  -v /etc/nginx-proxy/certs:/etc/nginx/certs:Z \
  nginx:alpine
```

Use code with caution.

Step 3: Open the RHEL 9 Firewall

By default, RHEL 9 blocks external ingress traffic. You need to explicitly open ports 80 and 443 via firewalld: \[[1](https://oneuptime.com/blog/post/2026-03-04-obtain-free-ssl-certificates-lets-encrypt-rhel-9/view), [2](https://www.tecmint.com/install-nginx-from-source/)\]

bash

```
sudo firewall-cmd --zone=public --add-service=http --permanent
sudo firewall-cmd --zone=public --add-service=https --permanent
sudo firewall-cmd --reload
```

Use code with caution.

Step 4: Update User Clients to Use HTTPS

Now that TLS is active, your engineers will change their API endpoint URLs from http on port 4000 to standard https without a port designation.

* **Claude Code CLI Environment Change:**  
  bash

```
export ANTHROPIC_BASE_URL="https://your-rhel-box-ip-or-domain"
```

*   
  Use code with caution.  
* **IDE Extensions / Claude Desktop JSON Base URL:**  
  json

```
"baseURL": "https://your-rhel-box-ip-or-domain/v1"
```

*   
  Use code with caution.  
  *(Note: If you used a self-signed certificate, developers may need to disable strict TLS verification in their IDE extension configurations, or append NODE\_EXTRA\_CA\_CERTS to their local machine environments for the Claude CLI to accept it.)*

Part 1: Specific Model Configurations (config.yaml)

Because you are using **Claude Code**, LiteLLM provides optimal performance when using the bedrock/invoke/ prefix rather than bedrock/converse/. It also needs to map standard Anthropic aliases (claude-3-5-sonnet, claude-3-haiku) so that IDE extensions recognize them automatically. \[[1](https://docs.litellm.ai/docs/tutorials/claude_responses_api), [2](https://www.truefoundry.com/blog/claude-code-with-litellm-setup-guide-when-to-use-truefoundry-ai-gateway)\]

Update your /app/config.yaml to include cross-region endpoints (if you use AWS Bedrock inference profiles) or regional IDs: \[[1](https://github.com/BerriAI/litellm/blob/main/docs/my-website/docs/pass_through/bedrock.md)\]

yaml

```
model_list:
  # 1. Claude 3.5 Sonnet (Primary Coding Model)
  - model_name: claude-3-5-sonnet
    litellm_params:
      model: bedrock/invoke/us.anthropic.claude-3-5-sonnet-20241022-v2:0
      aws_region_name: us-east-1

  - model_name: claude-3-5-sonnet-v2
    litellm_params:
      model: bedrock/invoke/us.anthropic.claude-3-5-sonnet-20241022-v2:0
      aws_region_name: us-east-1

  # 2. Claude 3.5 Haiku (Fast/Budget Coding Model)
  - model_name: claude-3-5-haiku
    litellm_params:
      model: bedrock/invoke/us.anthropic.claude-3-5-haiku-20241022-v1:0
      aws_region_name: us-east-1

  # 3. Standard Fallback Aliases for IDE Extensions
  - model_name: anthropic.claude-3-5-sonnet
    litellm_params:
      model: bedrock/invoke/us.anthropic.claude-3-5-sonnet-20241022-v2:0
      aws_region_name: us-east-1

router_settings:
  routing_strategy: simple-shuffle
  redis_ttl: 3600

litellm_settings:
  # Prevents Bedrock errors if IDEs try to send both temperature and top_p
  drop_params: true 
  # Strips experimental headers sent by Claude Code that Bedrock rejects
  drop_header: ["anthropic-beta"]
```

Use code with caution.

---

Part 2: Automating with Systemd via Podman

RHEL 9 handles container service orchestration via systemd natively using Podman. We will use systemd to manage container dependencies, ensuring PostgreSQL boots first, followed by LiteLLM, and finally Nginx. \[[1](https://oneuptime.com/blog/post/2026-03-04-generate-systemd-unit-files-podman-rhel-9/view), [2](https://oneuptime.com/blog/post/2026-02-02-podman-systemd-integration/view)\]

**1\. Generate Systemd Files**

Podman can automatically turn your existing active containers into systemd services. Run the following commands as root (or your deployment user): \[[1](https://www.redhat.com/en/blog/container-systemd-persist-reboot), [2](https://oneuptime.com/blog/post/2026-03-04-generate-systemd-unit-files-podman-rhel-9/view), [3](https://www.facebook.com/groups/GNUAndLinux/posts/10169607827800019/)\]

bash

```
# Navigate to the systemd directory
mkdir -p /etc/systemd/system/
cd /etc/systemd/system/

# Generate unit configurations directly from the running containers
podman generate systemd --new --name litellm-db > container-litellm-db.service
podman generate systemd --new --name litellm-proxy > container-litellm-proxy.service
podman generate systemd --new --name nginx-tls-proxy > container-nginx-tls-proxy.service
```

Use code with caution.

**2\. Configure Startup Dependencies**

To ensure the stack boots in the correct sequence after a server restart, you must establish order dependencies inside the unit files. \[[1](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)\]

Open /etc/systemd/system/container-litellm-proxy.service and add the database requirement to the \[Unit\] section:

ini

```
[Unit]
Description=Podman container-litellm-proxy.service
Requires=container-litellm-db.service
After=container-litellm-db.service
```

Use code with caution.

Open /etc/systemd/system/container-nginx-tls-proxy.service and add the proxy backend requirement to the \[Unit\] section:

ini

```
[Unit]
Description=Podman container-nginx-tls-proxy.service
Requires=container-litellm-proxy.service
After=container-litellm-proxy.service
```

Use code with caution.

**3\. Enable and Start the Services**

Reload the systemd daemon to discover the new configurations, then enable them to activate during RHEL 9 system boot: \[[1](https://www.it-hure.de/2024/02/podman-compose-and-systemd/)\]

bash

```
# Reload daemon
sudo systemctl daemon-reload

# Enable automatic startup on boot
sudo systemctl enable container-litellm-db.service
sudo systemctl enable container-litellm-proxy.service
sudo systemctl enable container-nginx-tls-proxy.service

# Start the edge proxy (which chains and triggers the other two)
sudo systemctl start container-nginx-tls-proxy.service
```

Use code with caution.

**4\. Verification**

Check the status of your architecture to verify everything runs inside isolated systemd processes: \[[1](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)\]

bash

```
sudo systemctl status container-nginx-tls-proxy.service
```

Use code with caution.

Your logs will route straight into journald, accessible anytime via journalctl \-u container-litellm-proxy.service \-f. \[[1](https://oneuptime.com/blog/post/2026-02-02-podman-systemd-integration/view)\]

Here is a production-ready bash script designed for RHEL 9\. It securely interacts with your LiteLLM container over the local loopback interface (localhost), generates a unique API key for an engineer, enforces the specific limits you define, and outputs a ready-to-use configuration snippet for their tools. \[[1](https://medium.com/@osomudeyazudonu/how-to-use-bash-python-for-real-devops-automation-with-5-production-use-cases-7cdb4b372525), [2](https://medium.com/towardsdev/10-bash-scripts-every-linux-sysadmin-should-have-ready-d18d5a538036)\]

The Automated Token Creation Script

Save this script as /usr/local/bin/create-ai-user.sh and make it executable with chmod \+x /usr/local/bin/create-ai-user.sh.

bash

```
#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# --- CONFIGURATION ---
# The master key you defined when starting your LiteLLM deployment
MASTER_PROXY_KEY="sk-your-master-proxy-key"
# We query localhost directly since the script runs on the host box
PROXY_URL="http://localhost:4000/key/generate"

# --- HELP MENU ---
usage() {
    echo "Usage: $0 -u <username> -b <budget_usd> -d <duration_days> [-r <rpm>] [-t <tpm>]"
    echo "Example: $0 -u dev_jdoe -b 50.00 -d 30 -r 100 -t 40000"
    exit 1
}

# --- PARSE ARGUMENTS ---
USERNAME=""
BUDGET=""
DURATION=""
RPM="100"      # Default requests per minute
TPM="40000"    # Default tokens per minute

while getopts "u:b:d:r:t:h" opt; do
    case ${opt} in
        u) USERNAME="$OPTARG" ;;
        b) BUDGET="$OPTARG" ;;
        d) DURATION="$OPTARG" ;;
        r) RPM="$OPTARG" ;;
        t) TPM="$OPTARG" ;;
        h|*) usage ;;
     Eagle)
    esac
done

# Validate required inputs
if [ -z "$USERNAME" ] || [ -z "$BUDGET" ] || [ -z "$DURATION" ]; then
    echo "Error: Missing required parameters." >&2
    usage
fi

# Append 'd' suffix to duration for LiteLLM's string parsing (e.g., "30d")
BUDGET_DURATION="${DURATION}d"

echo "Creating secure token for user: ${USERNAME}..."
echo "Applying limits: \$${BUDGET} cap, resetting every ${BUDGET_DURATION}, Max ${RPM} RPM / ${TPM} TPM."
echo "--------------------------------------------------------"

# --- EXECUTE API CALL ---
# LiteLLM tracks limits natively using these exact JSON payloads
RESPONSE=$(curl -s -X POST "$PROXY_URL" \
  -H "Authorization: Bearer $MASTER_PROXY_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"key_alias\": \"${USERNAME}\",
    \"max_budget\": ${BUDGET},
    \"budget_duration\": \"${BUDGET_DURATION}\",
    \"rpm_limit\": ${RPM},
    \"tpm_limit\": ${TPM}
  }")

# Extract generated key using basic string manipulation (prevents jq requirement)
# It targets the pattern "key": "sk-..."
if [[ "$RESPONSE" =~ \"key\":\"([^\"]+)\" ]]; then
    GENERATED_KEY="${BASH_REMATCH[1]}"
else
    echo "Error: Failed to generate token. API Response below:" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

# --- OUTPUT DEPLOYMENT TEMPLATE ---
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "SUCCESS! User token generated securely."
echo "--------------------------------------------------------"
echo "Token: $GENERATED_KEY"
echo "--------------------------------------------------------"
echo ""
echo "=== CLAUDE CODE CLI ENV CONFIG ==="
echo "export ANTHROPIC_BASE_URL=\"https://${SERVER_IP}\""
echo "export ANTHROPIC_API_KEY=\"${GENERATED_KEY}\""
echo ""
echo "=== VSCODE / IDE EXTENSION CONFIG ==="
echo "Provider: OpenAI-Compatible"
echo "Base URL: https://${SERVER_IP}/v1"
echo "API Key:  ${GENERATED_KEY}"
echo ""
echo "=== CLAUDE DESKTOP JSON CONFIG ==="
cat <<EOF
{
  "inference": {
    "provider": "openai-compatible",
    "baseURL": "https://${SERVER_IP}/v1",
    "apiKey": "${GENERATED_KEY}"
  }
}
EOF
```

Use code with caution.

How to Run the Script

**1\. Create a baseline user with standard limits ($50 budget, 30 days):**

bash

```
sudo /usr/local/bin/create-ai-user.sh -u john_doe -b 50.00 -d 30
```

Use code with caution.

**2\. Create a heavy senior developer user with higher throughput limits ($200 budget, 60 requests per minute):**

bash

```
sudo /usr/local/bin/create-ai-user.sh -u senior_dev -b 200.00 -d 30 -r 60 -t 80000
```

Use code with caution.

The script will instantly print out the direct string keys along with copy-pasteable configuration segments tailored specifically for your target Claude Code environments and VSCode properties.

Part 1: Token Revocation & Balance Checking Scripts

Save these tools under /usr/local/bin/ next to your creation script. They connect to the local loopback interface of your LiteLLM instance.

**1\. Balance Checking Script (/usr/local/bin/check-ai-user.sh)**

This script prints out exactly how much budget a user has consumed, their remaining balance, and their active request limits.

bash

```
#!/usr/bin/env bash
set -euo pipefail

MASTER_PROXY_KEY="sk-your-master-proxy-key"
PROXY_URL="http://localhost:4000/key/info"

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <key_or_alias>"
    echo "Example: $0 dev_jdoe"
    exit 1
fi

TARGET="$1"

echo "Querying LiteLLM registry for: ${TARGET}..."
echo "--------------------------------------------------------"

# Fetch key metadata fields natively via curl
RESPONSE=$(curl -s -X GET "${PROXY_URL}?key_alias=${TARGET}" \
  -H "Authorization: Bearer $MASTER_PROXY_KEY")

# Basic regex checks to pull variables out cleanly without requiring jq
if [[ "$RESPONSE" =~ \"max_budget\":([^, }]+) ]]; then MAX_B="${BASH_REMATCH[1]}"; else MAX_B="Unlimited"; fi
if [[ "$RESPONSE" =~ \"spend\":([^, }]+) ]]; then SPEND="${BASH_REMATCH[1]}"; else SPEND="0.00"; fi
if [[ "$RESPONSE" =~ \"rpm_limit\":([^, }]+) ]]; then RPM="${BASH_REMATCH[1]}"; else RPM="Default"; fi

# Simple inline layout format
echo "Account Status Summary:"
echo "  - Identity Alias:  $TARGET"
echo "  - Total Budget:    \$$MAX_B"
echo "  - Total Consumed:  \$$SPEND"
echo "  - Active Rate:     $RPM Requests/Min"
echo "--------------------------------------------------------"
```

Use code with caution.

**2\. Revocation Script (/usr/local/bin/revoke-ai-user.sh)**

This tool instantly deactivates a user key, blocking further access across Claude Code and connected IDE extensions.

bash

```
#!/usr/bin/env bash
set -euo pipefail

MASTER_PROXY_KEY="sk-your-master-proxy-key"
PROXY_URL="http://localhost:4000/key/delete"

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <key_or_alias>"
    exit 1
fi

TARGET="$1"

echo "Sending hard revocation instruction for: ${TARGET}..."

RESPONSE=$(curl -s -X POST "$PROXY_URL" \
  -H "Authorization: Bearer $MASTER_PROXY_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"keys\": [\"${TARGET}\"]}")

if [[ "$RESPONSE" =~ "success" ]]; then
    echo "SUCCESS: Key access has been permanently revoked."
else
    echo "Error processing request. Server response:"
    echo "$RESPONSE"
fi
```

Use code with caution.

Make both tools executable:

bash

```
chmod +x /usr/local/bin/check-ai-user.sh /usr/local/bin/revoke-ai-user.sh
```

Use code with caution.  
---

Part 2: Automated Container Log Rotation

Podman on RHEL 9 writes container outputs directly into the host machine's system journal system (journald) or local text files depending on your system configuration. You must set limits at both the container layer and system daemon layer to ensure your storage stays optimized. \[[1](https://cloudlytics.com/how-to-monitor-kubernetes-audit-logs/)\]

**1\. Podman-Level Container Log Limits**

Modify your global container configuration so that any log text files generated natively by Podman engines automatically clip and loop.

Open or create the Podman containers configuration file:

bash

```
sudo vi /etc/containers/containers.conf
```

Use code with caution.

Add or find the \[containers\] section and set strict file caps:

ini

```
[containers]
log_driver = "k8s-file"
log_size_max = 52428800  # Strict 50MB file size limit per container
```

Use code with caution.

**2\. Systemd Journald Optimization**

Because your containers are managed via systemd units, their stdout streams are indexed into journald. To keep overall system logs from expanding indefinitely, enforce absolute boundaries. \[[1](https://docs.redhat.com/en/documentation/red_hat_openstack_platform/16.0/html/transitioning_to_containerized_services/working-with-containerized-services), [2](https://oneuptime.com/blog/post/2026-03-17-configure-log-drivers-quadlet/view)\]

Open the system journal configuration file:

bash

```
sudo vi /etc/systemd/journald.conf
```

Use code with caution.

Uncomment and adjust these key properties inside the \[Journal\] section:

ini

```
[Journal]
SystemMaxUse=2G       # Never allow the total system log storage to exceed 2 Gigabytes
SystemMaxFileSize=100M # Automatically split individual internal log chunks at 100MB
MaxRetentionSec=14day # Automatically purge any log data older than two weeks
```

Use code with caution.

Save and close the file, then restart the logging subsystem to apply the constraints immediately:

bash

```
sudo systemctl restart systemd-journald
```

Use code with caution.

Enabling **Prompt Caching** on Amazon Bedrock via LiteLLM drastically slices your operational bills, cutting input token fees by **up to 90%** for long developer conversations and massive codebase contexts. \[[1](https://aws.amazon.com/blogs/machine-learning/effectively-use-prompt-caching-on-amazon-bedrock/), [2](https://docs.litellm.ai/docs/tutorials/prompt_caching), [3](https://www.linkedin.com/posts/krish-d_thrilled-to-support-aws-bedrock-tool-prompt-activity-7362407268908199937-IZ_w)\]

Since your engineers are using external tools (Claude Code, VSCode, Claude Desktop) that don't pass manual cache headers, you must instruct LiteLLM to **auto-inject caching checkpoints globally** right inside your central config.yaml file. \[[1](https://docs.litellm.ai/docs/tutorials/prompt_caching), [2](https://docs.litellm.ai/docs/tutorials/prompt_caching)\]

---

Step 1: Update your /app/config.yaml with Auto-Caching Rules

Modify your existing model configurations to enable the cache\_control\_injection\_points parameter. This flags LiteLLM to automatically place cache hooks behind long system headers or right before the latest developer messages. \[[1](https://docs.litellm.ai/docs/tutorials/prompt_caching)\]

yaml

```
model_list:
  # 1. Claude 3.5 Sonnet
  - model_name: claude-3-5-sonnet
    litellm_params:
      model: bedrock/invoke/us.anthropic.claude-3-5-sonnet-20241022-v2:0
      aws_region_name: us-east-1
      # AUTO-CACHING LOGIC
      cache_control_injection_points:
        - location: "user"     # Auto-cache historical chat turns right up to the user message
        - location: "system"   # Auto-cache giant system instructions/codebase maps

  # 2. Claude 3.5 Haiku
  - model_name: claude-3-5-haiku
    litellm_params:
      model: bedrock/invoke/us.anthropic.claude-3-5-haiku-20241022-v1:0
      aws_region_name: us-east-1
      cache_control_injection_points:
        - location: "user"
        - location: "system"

  # 3. Standard Fallback Aliases
  - model_name: anthropic.claude-3-5-sonnet
    litellm_params:
      model: bedrock/invoke/us.anthropic.claude-3-5-sonnet-20241022-v2:0
      aws_region_name: us-east-1
      cache_control_injection_points:
        - location: "user"
        - location: "system"

router_settings:
  routing_strategy: simple-shuffle
  redis_ttl: 3600

litellm_settings:
  drop_params: true 
  drop_header: ["anthropic-beta"]
```

Use code with caution.

Apply these edits instantly by rebooting your Nginx orchestration setup:

bash

```
sudo systemctl restart container-nginx-tls-proxy.service
```

Use code with caution.

---

Step 2: Critical Bedrock Infrastructure Requirements

For caching to trigger successfully, the incoming requests from your engineers must meet Amazon Bedrock’s architecture constraints: \[[1](https://docs.litellm.ai/docs/completion/prompt_caching)\]

1. **Token Minimums**: Amazon Bedrock requires a **minimum threshold of tokens** before a cache point can be created. For Claude 3.5 Sonnet/Haiku, the prompt must contain **at least 1,024 tokens**. Prompts smaller than this limit bypass caching entirely without throwing errors, processing at normal baseline pricing. \[[1](https://docs.litellm.ai/docs/completion/prompt_caching), [2](https://www.reddit.com/r/aws/comments/1toi6fw/prompt_caching_for_bedrock_agents/), [3](https://docs.litellm.ai/docs/completion/prompt_caching), [4](https://www.linkedin.com/pulse/building-chat-agent-using-aws-bedrock-prompt-caching-van-t-land-pkoae), [5](https://medium.com/@ericajayasundera/understanding-prompt-caching-in-large-language-model-apis-4c6470b5dea7)\]  
2. **Context Matching**: Caching matches your exact text string from left to right. Tools like **Claude Code CLI** benefit heavily because they pass a static "system prompt" context containing your file directories across every command. \[[1](https://aws.amazon.com/blogs/machine-learning/effectively-use-prompt-caching-on-amazon-bedrock/), [2](https://github.com/tag1consulting/ai-pr-review/issues/122)\]  
3. **Cache Duration (TTL)**: By default, Bedrock preserves the compilation cache for **5 minutes** from the last request. Every hit by a developer resets that 5-minute window. \[[1](https://medium.com/@dustin_44710/building-a-production-ready-amazon-bedrock-client-lessons-from-seddle-45fff44a03d2), [2](https://caylent.com/blog/prompt-caching-saving-time-and-money-in-llm-applications), [3](https://github.com/BerriAI/litellm/issues/19848)\]

---

Step 3: Verifying Your Financial Savings

LiteLLM tracks cache hits and passes them transparently to your user dashboard or logs. \[[1](https://docs.litellm.ai/docs/tutorials/prompt_caching), [2](https://github.com/strands-agents/sdk-python/issues/937), [3](https://docs.litellm.ai/docs/tutorials/prompt_caching)\]

To audit if your setup is active, watch the JSON responses returned by LiteLLM using journalctl \-u container-litellm-proxy.service \-f. Look closely inside the "usage" metric block: \[[1](https://github.com/strands-agents/sdk-python/issues/937)\]

json

```
"usage": {
  "prompt_tokens": 4500,
  "completion_tokens": 320,
  "total_tokens": 4820,
  "prompt_tokens_details": {
    "cached_tokens": 3400
  }
}
```

Use code with caution.

If you see **cached\_tokens matching your input metrics**, LiteLLM is successfully intercepting the call and saving you up to 90% on that request\! \[[1](https://github.com/strands-agents/sdk-python/issues/937), [2](https://aws.amazon.com/blogs/machine-learning/effectively-use-prompt-caching-on-amazon-bedrock/)\]

Now that your core system architecture, routing protocols, TLS encryption, orchestration layer, and token-caching engines are fully optimized, would you like to review **IAM permissions needed on AWS** to grant Bedrock model access, or are you **ready to deploy**?

