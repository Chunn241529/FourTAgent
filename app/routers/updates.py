from fastapi import APIRouter, HTTPException
import httpx
from typing import Optional
import re
import os

router = APIRouter(prefix="/api/updates", tags=["updates"])

# GitHub repository info - configure via environment variables
GITHUB_OWNER = os.getenv("GITHUB_OWNER", "your-github-username")
GITHUB_REPO = os.getenv("GITHUB_REPO", "4T_task")


@router.get("/version")
async def get_latest_version():
    """
    Fetch the latest release version from GitHub Releases.
    Returns version info and download URLs for Windows and Linux.
    """
    try:
        # Fetch latest release from GitHub API
        url = (
            f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/releases/latest"
        )

        async with httpx.AsyncClient() as client:
            response = await client.get(
                url, headers={"Accept": "application/vnd.github+json"}, timeout=10.0
            )

            if response.status_code == 404:
                # No releases yet
                return {"version": None, "message": "No releases available"}

            response.raise_for_status()
            release_data = response.json()

        # Extract version from tag (e.g., "v1.0.0" -> "1.0.0")
        tag_name = release_data.get("tag_name", "")
        version = tag_name.lstrip("v")

        # Extract download URLs from assets
        # Extract download URLs from assets
        assets = release_data.get("assets", [])
        windows_url = None
        linux_url = None

        # Debug: list all asset names
        asset_names = [a.get("name", "") for a in assets]
        print(f"Found assets: {asset_names}")

        for asset in assets:
            name = asset.get("name", "").lower()
            download_url = asset.get("browser_download_url")

            if "windows" in name and download_url:
                windows_url = download_url
            elif "linux" in name and download_url:
                linux_url = download_url

        # Fallback for Linux: Look for any ZIP file if no explicit "linux" asset found
        # This handles cases like "Lumina.zip"
        if not linux_url:
            for asset in assets:
                name = asset.get("name", "").lower()
                download_url = asset.get("browser_download_url")
                if (
                    name.endswith(".zip")
                    and "windows" not in name
                    and "win" not in name
                    and "mac" not in name
                    and "osx" not in name
                ):
                    linux_url = download_url
                    break

        # Get changelog from release body
        changelog = release_data.get("body", "")

        return {
            "version": version,
            "tag_name": tag_name,
            "windows_url": windows_url,
            "linux_url": linux_url,
            "changelog": changelog,
            "published_at": release_data.get("published_at"),
            "debug_assets": asset_names,
        }

    except httpx.HTTPError as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to fetch release info: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")
