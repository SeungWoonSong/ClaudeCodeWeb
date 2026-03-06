#!/usr/bin/env python3
"""Self-hosted Mem0 MCP server for Claude Code.

Connects to a self-hosted Mem0 REST API using Bearer authentication.
Uses standard Mem0 Platform REST endpoints (/v1/*, /v2/*).

Required env vars:
    MEM0_HOST     - Base URL of your Mem0 server (e.g. https://mem0.example.com)
    MEM0_API_KEY  - Bearer token for authentication

Optional env vars:
    MEM0_USER_ID  - Default user ID for memory scoping (default: pm-default)
"""

import json
import os
import sys
from typing import Optional

import httpx
from mcp.server.fastmcp import FastMCP

HOST = os.environ.get("MEM0_HOST", "")
API_KEY = os.environ.get("MEM0_API_KEY", "")
DEFAULT_USER_ID = os.environ.get("MEM0_USER_ID", "pm-default")

if not HOST or not API_KEY:
    print("ERROR: MEM0_HOST and MEM0_API_KEY must be set", file=sys.stderr)
    sys.exit(1)

mcp = FastMCP("mem0")

_client = httpx.Client(
    base_url=HOST.rstrip("/"),
    headers={
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json",
    },
    timeout=60,
)


def _request(method: str, path: str, **kwargs):
    """Make HTTP request to Mem0 API and return parsed JSON."""
    resp = getattr(_client, method)(path, **kwargs)
    resp.raise_for_status()
    return resp.json()


@mcp.tool()
def add_memory(
    text: str,
    user_id: Optional[str] = None,
    metadata: Optional[dict] = None,
) -> str:
    """Store a new memory. Text is extracted and stored as semantic memory."""
    payload = {
        "messages": [{"role": "user", "content": text}],
        "user_id": user_id or DEFAULT_USER_ID,
    }
    if metadata:
        payload["metadata"] = metadata
    result = _request("post", "/v1/memories/", json=payload)
    return json.dumps(result, ensure_ascii=False)


@mcp.tool()
def search_memories(
    query: str,
    user_id: Optional[str] = None,
    limit: int = 10,
) -> str:
    """Search memories by semantic similarity. Returns ranked results."""
    payload = {
        "query": query,
        "user_id": user_id or DEFAULT_USER_ID,
        "top_k": limit,
    }
    result = _request("post", "/v2/memories/search/", json=payload)
    return json.dumps(result, ensure_ascii=False)


@mcp.tool()
def get_memories(user_id: Optional[str] = None) -> str:
    """List all memories for a user."""
    payload = {"user_id": user_id or DEFAULT_USER_ID}
    result = _request("post", "/v2/memories/", json=payload)
    return json.dumps(result, ensure_ascii=False)


@mcp.tool()
def get_memory(memory_id: str) -> str:
    """Get a single memory by its ID."""
    result = _request("get", f"/v1/memories/{memory_id}/")
    return json.dumps(result, ensure_ascii=False)


@mcp.tool()
def update_memory(memory_id: str, text: str) -> str:
    """Update an existing memory's text content."""
    result = _request("put", f"/v1/memories/{memory_id}/", json={"text": text})
    return json.dumps(result, ensure_ascii=False)


@mcp.tool()
def delete_memory(memory_id: str) -> str:
    """Delete a single memory by its ID."""
    result = _request("delete", f"/v1/memories/{memory_id}/")
    return json.dumps(result, ensure_ascii=False)


@mcp.tool()
def delete_all_memories(user_id: Optional[str] = None) -> str:
    """Delete all memories for a user. Use with caution."""
    params = {"user_id": user_id or DEFAULT_USER_ID}
    result = _request("delete", "/v1/memories/", params=params)
    return json.dumps(result, ensure_ascii=False)


@mcp.tool()
def list_entities() -> str:
    """List all users, agents, and apps that have stored memories."""
    result = _request("get", "/v1/entities/")
    return json.dumps(result, ensure_ascii=False)


if __name__ == "__main__":
    mcp.run(transport="stdio")
