# Bruno Demo Collection

Open this folder as a collection in Bruno. Start the Terraform environment first.

1. Select **Test** or **Production Demo** in Bruno's environment selector.
2. Open the selected environment's settings and fill in the secret variables **appAKey** and **appBKey**. Keep them marked as secrets, not ordinary variables.
3. Run the numbered requests. Headers and JSON bodies are already configured. The Auth tab is deliberately set to None because authentication uses the explicit `X-Api-Key` header.

Retrieve keys privately for Test:

```sh
docker exec product-order-test-gateway cat /var/lib/lab-secrets/app-a.key
docker exec product-order-test-gateway cat /var/lib/lab-secrets/app-b.key
```

For Production Demo, replace the container name with `product-order-production-gateway`. Test and production keys are independent. These commands display existing secrets; never share their output or paste values into `.bru` files. Secret-variable declarations are included, but no credential values are shipped. Review any exports before sharing.

## Demonstrate

- **No auth:** 401. Repeat after warming the product cache to show authentication still applies.
- **App A / App B GET:** 200 for approved clients. Change the product ID to `2` or an unknown ID to show routing and a backend 404.
- **Caching:** repeat the same client's GET; inspect `X-Cache-Status` and the retained backend request ID. A warm cache can show two Hits. Wait beyond 5 seconds in Test or 30 seconds in Production Demo for expiry.
- **POST:** 201 for the fixed valid body. Repeating it should produce different backend request IDs, not different order IDs: this is a stateless stub. Quantity 0 gives 400.
- **Invalid key:** temporarily replace the header value with `not-a-valid-key`, send, then restore the variable reference. Expect 401.
- **Rate limit:** use the existing `tests/demo.mjs path=get requests=1000` from the submission root, then inspect quota headers in Bruno. Quotas are shared and may recover before the next manual request. Run heavy traffic last.

If you change Terraform's host ports, update the corresponding Bruno `baseUrl`. After explicit credential rotation and a successful gateway restart, update the local secret variable. Normal restarts reuse the saved key.

This collection has no scripts, automatic assertions or credential-retrieval hooks. It is optional demonstration support. It has not been imported or executed by the assistant; compare actual responses with the expectations above.
