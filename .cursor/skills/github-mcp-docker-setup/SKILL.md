---
name: github-mcp-docker-setup
description: Helps users set up GitHub MCP server locally via Docker with Actions support. Use when the user wants to install or configure the GitHub MCP, run it from Docker, enable workflow trigger/list tools, or asks about GitHub MCP setup, Docker MCP, or Actions toolset.
---

# GitHub MCP Setup (Docker + Actions)

Guides setup of the GitHub MCP server locally using Docker, with the **actions** toolset enabled for workflow trigger, list runs, and job logs.

**Prerequisites**: Docker installed and running.

## Setup Steps

### 1. Pull the image

```bash
docker pull ghcr.io/github/github-mcp-server
```

### 2. Create or update GitHub Personal Access Token

- Go to [GitHub → Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens/new)
- Create a token with scopes: `repo`, `read:org`, `read:packages` (for Docker image)
- For Actions: token needs `workflow` (or equivalent) for trigger/run operations

### 3. Add server to Cursor MCP config

Edit `~/.cursor/mcp.json` and add/update the `github` server:

```json
{
  "mcpServers": {
    "github": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        "-e",
        "GITHUB_PERSONAL_ACCESS_TOKEN",
        "-e",
        "GITHUB_TOOLSETS",
        "ghcr.io/github/github-mcp-server"
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_GITHUB_PAT_HERE",
        "GITHUB_TOOLSETS": "default,actions"
      }
    }
  }
}
```

Replace `YOUR_GITHUB_PAT_HERE` with the user's token. Never commit tokens.

### 4. Validate access

Wait ~2 minutes for Cursor to pick up the MCP config. Then verify the agent has access to Actions tools in the current session:

- Call `actions_list` with `method: "list_workflows"`, `owner`, and `repo` for a known repository
- If the call succeeds and returns data (or `total_count`), Actions tools are working

## Toolset Reference

| Value | Includes |
|-------|----------|
| `default` | context, repos, issues, pull_requests, users |
| `actions` | workflow list/trigger, run details, job logs, artifacts |

Use `GITHUB_TOOLSETS=all` to enable every toolset. See [github/github-mcp-server](https://github.com/github/github-mcp-server#tool-configuration).

## Troubleshooting

- **Docker daemon not running**: Start Docker Desktop or the Docker service.
- **Token errors**: Verify token scopes include `repo` and `workflow` (for Actions).
- **Actions tools missing**: Ensure `GITHUB_TOOLSETS` includes `actions`.
