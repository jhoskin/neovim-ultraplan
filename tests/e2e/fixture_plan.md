# Sample plan

## Context

The widget service returns stale data after a deploy because the cache
is never invalidated.

## Approach

1. Add a version key to every cache entry.
2. Bump the key on deploy.

```bash
# not a heading: a shell comment inside a fence
make deploy
```

### Risks

Cold caches on every deploy.

## Tests

Unit test the key derivation and an e2e test that deploys twice.
