import os
import shutil
import logging
from typing import List, Dict, Any, Optional
from pathlib import Path
import stat

logger = logging.getLogger(__name__)


class CloudFileService:
    """
    Secure file management service restricted to `user_data/cloud/{user_id}`.
    Allows LLM to manage files autonomously within a safe sandbox.
    """

    BASE_STORAGE_PATH = "user_data/cloud"

    @staticmethod
    def _get_user_root(user_id: int) -> str:
        """Returns the absolute path to the user's root cloud directory."""
        # Ensure base directory exists
        os.makedirs(CloudFileService.BASE_STORAGE_PATH, exist_ok=True)

        user_root = os.path.abspath(
            os.path.join(CloudFileService.BASE_STORAGE_PATH, str(user_id))
        )
        if not os.path.exists(user_root):
            os.makedirs(user_root, exist_ok=True)
        return user_root

    @staticmethod
    def _get_secure_path(user_id: int, relative_path: str) -> str:
        """
        Resolves and validates a path to ensure it's inside the user's root.
        Raises ValueError if path attempts traversal.
        """
        user_root = CloudFileService._get_user_root(user_id)

        # Handle root path request
        if relative_path == "/" or relative_path == "." or not relative_path:
            return user_root

        # Normalize path
        try:
            # Join and resolve
            # Ensure relative_path is treated as relative by stripping leading slashes
            clean_relative = relative_path.lstrip("/").lstrip("\\")
            target_path = os.path.abspath(os.path.join(user_root, clean_relative))

            # Check for directory traversal
            if not target_path.startswith(user_root):
                raise ValueError(
                    f"Access denied: Path '{relative_path}' traverses outside user storage."
                )

            return target_path
        except Exception as e:
            raise ValueError(f"Invalid path: {e}")

    @staticmethod
    def list_files(user_id: int, directory: str = "/") -> List[Dict[str, Any]]:
        """List files and directories in the specified path."""
        try:
            target_path = CloudFileService._get_secure_path(user_id, directory)

            if not os.path.exists(target_path):
                return []  # Or raise error? Empty list is safer for LLM.

            if not os.path.isdir(target_path):
                return [
                    {
                        "name": os.path.basename(target_path),
                        "type": "file",
                        "path": directory,
                    }
                ]

            items = []
            for entry in os.scandir(target_path):
                # Calculate relative path from user root for display
                rel_path = os.path.relpath(
                    entry.path, CloudFileService._get_user_root(user_id)
                )

                items.append(
                    {
                        "name": entry.name,
                        "type": "directory" if entry.is_dir() else "file",
                        "path": rel_path,
                        "size": entry.stat().st_size if entry.is_file() else 0,
                    }
                )

            # Sort: Directories first, then files
            items.sort(key=lambda x: (x["type"] != "directory", x["name"]))
            return items

        except Exception as e:
            logger.error(f"Error listing files for user {user_id}: {e}")
            raise ValueError(f"Failed to list files: {str(e)}")

    @staticmethod
    def search_files(user_id: int, query: str) -> List[Dict[str, Any]]:
        """
        Recursively search for files matching the query (substring match or glob).
        Returns list of file info dicts.
        """
        try:
            user_root = CloudFileService._get_user_root(user_id)
            results = []

            # Normalize query (simple case-insensitive substring or glob)
            query_lower = query.lower()
            is_glob = "*" in query or "?" in query

            import fnmatch

            for dirpath, _, filenames in os.walk(user_root):
                for filename in filenames:
                    # Calculate relative path
                    full_path = os.path.join(dirpath, filename)
                    rel_path = os.path.relpath(full_path, user_root)

                    match = False
                    if is_glob:
                        if fnmatch.fnmatch(filename.lower(), query_lower):
                            match = True
                    else:
                        if query_lower in filename.lower():
                            match = True

                    if match:
                        results.append(
                            {
                                "name": filename,
                                "type": "file",
                                "path": rel_path,
                                "size": os.path.getsize(full_path),
                            }
                        )

                    if len(results) >= 50:  # Limit results
                        return results

            return results

        except Exception as e:
            logger.error(f"Error searching files for user {user_id}: {e}")
            raise ValueError(f"Failed to search files: {str(e)}")

    @staticmethod
    def get_file_info(user_id: int, path: str) -> Dict[str, Any]:
        """Get info about a specific file or directory."""
        try:
            target_path = CloudFileService._get_secure_path(user_id, path)

            if not os.path.exists(target_path):
                raise FileNotFoundError(f"Path not found: {path}")

            is_dir = os.path.isdir(target_path)
            size = os.path.getsize(target_path) if not is_dir else 0

            # Calculate relative path from user root to be consistent
            user_root = CloudFileService._get_user_root(user_id)
            rel_path = os.path.relpath(target_path, user_root)

            return {
                "name": os.path.basename(target_path),
                "type": "directory" if is_dir else "file",
                "path": rel_path,
                "size": size,
            }

        except Exception as e:
            logger.error(f"Error getting info for {path} (user {user_id}): {e}")
            raise e

    @staticmethod
    def read_file(user_id: int, path: str) -> str:
        """Read content of a file."""
        try:
            target_path = CloudFileService._get_secure_path(user_id, path)

            if not os.path.exists(target_path):
                raise FileNotFoundError(f"File not found: {path}")

            if os.path.isdir(target_path):
                raise IsADirectoryError(f"Path is a directory: {path}")

            # Check file size limit (e.g. 5MB) to prevent memory issues
            if os.path.getsize(target_path) > 5 * 1024 * 1024:
                raise ValueError("File too large to read directly (max 5MB).")

            with open(target_path, "r", encoding="utf-8") as f:
                return f.read()

        except UnicodeDecodeError:
            return "[Binary content or non-UTF8 file]"
        except Exception as e:
            logger.error(f"Error reading file {path} for user {user_id}: {e}")
            raise e

    @staticmethod
    def create_file(user_id: int, path: str, content: str) -> Dict[str, Any]:
        """Create or overwrite a file with content. Auto-creates parent directories."""
        try:
            target_path = CloudFileService._get_secure_path(user_id, path)

            # Prevent overwriting directories
            if os.path.isdir(target_path):
                raise IsADirectoryError(f"Destination is an existing directory: {path}")

            # Create parent directories
            os.makedirs(os.path.dirname(target_path), exist_ok=True)

            with open(target_path, "w", encoding="utf-8") as f:
                f.write(content)

            return {
                "success": True,
                "message": f"File created: {path}",
                "path": path,
                "size": len(content),
            }

        except Exception as e:
            logger.error(f"Error creating file {path} for user {user_id}: {e}")
            raise e

    @staticmethod
    def delete_file(user_id: int, path: str) -> Dict[str, Any]:
        """Delete a file or empty directory."""
        try:
            target_path = CloudFileService._get_secure_path(user_id, path)

            if not os.path.exists(target_path):
                raise FileNotFoundError(f"Path not found: {path}")

            if os.path.isdir(target_path):
                # Only allow deleting empty directories or generic delete?
                # Let's use rmdir for safety, or prompt for recursive?
                # User asked for "delete (all)", implying robust delete.
                # Let's use delete_directory for recursion, here implies single item.
                try:
                    os.rmdir(target_path)
                except OSError:
                    # Not empty
                    raise BlockingIOError(
                        f"Directory not empty: {path}. Use delete_folder to remove recursively."
                    )
            else:
                os.remove(target_path)

            return {"success": True, "message": f"Deleted: {path}"}

        except Exception as e:
            logger.error(f"Error deleting {path} for user {user_id}: {e}")
            raise e

    @staticmethod
    def create_folder(user_id: int, path: str) -> Dict[str, Any]:
        """Create a directory (recursive)."""
        try:
            target_path = CloudFileService._get_secure_path(user_id, path)

            if os.path.exists(target_path):
                if os.path.isdir(target_path):
                    return {
                        "success": True,
                        "message": f"Directory already exists: {path}",
                    }
                else:
                    raise FileExistsError(f"Path exists and is a file: {path}")

            os.makedirs(target_path, exist_ok=True)
            return {"success": True, "message": f"Directory created: {path}"}

        except Exception as e:
            logger.error(f"Error creating folder {path} for user {user_id}: {e}")
            raise e

    @staticmethod
    def delete_folder(user_id: int, path: str) -> Dict[str, Any]:
        """Delete a directory recursively."""
        try:
            target_path = CloudFileService._get_secure_path(user_id, path)

            # Prevent deleting root
            if target_path == CloudFileService._get_user_root(user_id):
                raise ValueError("Cannot delete root cloud directory.")

            if not os.path.exists(target_path):
                raise FileNotFoundError(f"Directory not found: {path}")

            if not os.path.isdir(target_path):
                raise NotADirectoryError(f"Path is not a directory: {path}")

            shutil.rmtree(target_path)
            return {
                "success": True,
                "message": f"Directory deleted recursively: {path}",
            }

        except Exception as e:
            logger.error(f"Error deleting folder {path} for user {user_id}: {e}")
            raise e
