**Project Descriptions: Creating an API Gateway to manage traffic for a backend application**

**Overview:**
We used terraform as IaC, provision the docker env and to orchestrate our api gateway and a small .net mock backend exposing two endpoints providing dummy response.  
Kong api gateway with few capabilities included such as, api-key auth, rate limiting, upstream time out, request size limit (16kb), container health check, logging.  
A demo test file (demo.mjs), a small js script to test a few capabilities and also tinkering a few flags to test the gateway capabiltiies. (optionally included)


**Assumptions:**
- I used a small dummy backend service to inspect the gateway behaviour case, the main important part is the API gateway which sits between the client and the backend service. 
- Approved applications can access both endpoints.
- The case does not guarantee idempotency for order creation so repeated post requests are not safe.
- One gateway and one backend per environment are sufficient for the exercise. High availability and distributed rate limiting are outside for this case’s scope
- Actual traffic/backend capacities are unknown so the static values are only for demonstration purpose

**Decision and tradeoffs:**
- Using key-auth authentication and saving inside docker volume and read later in test file which is not something we should do in a prod environment though, we need to have a good key vault setup or secret store or ideally use secretless federated creds in real scenarios. 
- Caching strategy includes a static x amount (5sec/30sec for test/prod). But no cache invalidation strategy before ttl.  
- Disabling automatic retry on ( although this doesn’t guarantee duplicate prevention in the backend ) 
- Rate limiting is shared.  It protects the backend, but one noisy client can consume the allowance and affect others. (req per second 10/20 , and req per min 20/600, test and prod accordingly)
- Keeping a shared terraform state, for this interview purpose both test and prod env shares the same tf state. Just for simplicity. Ideally independently managed env should have its own state

**Implementation and How to run:** 


**Implemented Features:**
- Terraform creates the local Docker environments,
- Kong routes requests, authenticates API keys, applies rate limits, and caches eligible product responses. 
- Kong also configures upstream timeouts, disabled automatic retries, request-size limits, api access log

**Illustrative Parts:**
- The .NET backend returns fixed responses. It does not create or store real orders.
- The optional demo.mjs client sends requests to demonstrate gateway behavior.
- The “prod” environment is another local Docker deployment, not a production cloud setup.

**Prerequisites**
- Terraform 1.5 or later
- Docker installed and running locally.
- Node.js 22.12+ only for the optional demo script.
- Available host ports 8001 and 8002, or adjusted configuration in:
- `infra/environments/test.json` for test, currently 8001.
- `infra/environments/production.json` for the production demo, currently 8002.
- Bruno for api testing
- Optionally Node 22+ for `tests/demo.mjs`, it has hardcoded port, change and adjust if necessary 

**How to run:**

cd into infra dir (or, run using `terraform -chdir=infra <command>`)

Run 

```sh
terraform init
terraform workspace select default
terraform validate
terraform plan
terraform apply
```

If you need to destroy both profiles and their credentials. Run “`terraform destroy`” command 

**Try the API:**

From cli: Without X-Api-Key header:  “`curl -i http://localhost:8001/products/1`”  -> will return 401 unauthorized 


Get the key using: “`docker exec product-order-test-gateway cat /var/lib/lab-secrets/app-a.key`” or “`docker exec product-order-test-gateway cat /var/lib/lab-secrets/app-b.key`” 

Use Bruno/postman/insomnia or similar add the X-Api-Key in the header and pass the printed key you will receive the response. 

(Alternatively, You can use the Bruno collection in the repo add the collection to your Bruno library. its preloaded with header and body required)

**Endpoints:**
- GET `http://localhost:8001/products/1` with X-Api-Key header
- POST `http://localhost:8001/orders` with body `{"productId":"2","quantity":2}` and X-Api-Keyheader

To Demonstrate capabilities like rate limit and cache Go inside tests directory

**Now, to test rate limit:** 
Run: 	“`node demo.mjs env=test path=get requests=1000`”

**Response example:** 

```text
test: GET, 1000 request(s), port 8001.
HTTP status counts: { '200': 30, '429': 970 }
```

30 of the request gets 200 response and 970 requests got 429 too many request response

**To test caching run this twice within 5 sec(defined static ttl value for test):** 
Run: 	“`node demo.mjs env=test path=get requests=1`”

**First response:**

```text
test: GET, 1 request(s), port 8001.
Request 1: HTTP 200
x-cache-status: Miss
x-backend-request-id: 6ab9babb096a464699ee0489ffb8f4ad
x-ratelimit-remaining-second: 9
x-ratelimit-remaining-minute: 19
retry-after: -
{"id":"1","name":"Example Product","price":100,"currency":"DKK"}
HTTP status counts: { '200': 1 }
```

**Second Response:**

```text
test: GET, 1 request(s), port 8001.
Request 1: HTTP 200
x-cache-status: Hit
x-backend-request-id: 6ab9babb096a464699ee0489ffb8f4ad
x-ratelimit-remaining-second: 9
x-ratelimit-remaining-minute: 18
retry-after: -
{"id":"1","name":"Example Product","price":100,"currency":"DKK"}
HTTP status counts: { '200': 1 }
```

Second Response, returning from a cached response from the gateway instead reaching out to the backend. After 5 sec the cache will be invalidated and will hit the backend again to get it. 

**Possible Improvement for this solution:**

**Caching:** Exploring explicit cache invalidation when product details change. So client doesnt need to wait for ttl expiry or receive stale data. 

**Per client Rate limiting:** If client fairness becomes important, I would investigate per-client rate limits alongside the shared limit, ( shared limit is also for protecting our backend)

**Authentication Strategy:** There is no automated process to securely distribute keys to clients. Our demo script reads the key from the gateway's Docker volume, which is only a local testing convenience.  
For prod I would use Key Vault with controlled client access and coordinated gateway provisioning and rotation.  
Alternatively, workload identity could provide short-lived Entra tokens, validated by a compatible gateway integration  
Showcase observability with dashboard, (fx. using prometheus plugin, and grafana dashboard)

**Reference material used:** 

**Kong Plugins:**
- Key Auth (https://developer.konghq.com/plugins/key-auth/) - validates application API keys.
- Rate Limiting (https://developer.konghq.com/plugins/rate-limiting/) - limits request traffic.
- Proxy Cache (https://developer.konghq.com/plugins/proxy-cache/) - caches eligible product responses.

**Configuration:** 
- Kong DB-less Configuration (https://developer.konghq.com/gateway/db-less-mode/) - loading declarative configuration without a database.
- Terraform Documentation (https://developer.hashicorp.com/terraform/docs) - Terraform concepts and commands.
- Terraform Docker Provider (https://registry.terraform.io/providers/kreuzwerker/docker/4.6.0/docs) - the provider version used to manage our Docker resources.

**Code Assist:**
- GitHub Copilot assistance for ideation, code drafting, and review
