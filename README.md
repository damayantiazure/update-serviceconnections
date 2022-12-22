# Automating Service Connection Updates!


1. Updating Service connections which are manually created with type ARM service connection and with SPN manual auth   
2. Iterating through service connections, getting the Service principals and the keys
3. Deleting those and updating with new keys and also sets the expiry dates
4. Updating back the service connections with new keys

Using:
- Azure CLI
- DevOps YML Pipelines
- Devops rest APIs

