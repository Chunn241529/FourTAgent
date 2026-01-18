import logging
from typing import List, Optional, Dict
from sqlalchemy.orm import Session
from app.models import User
from datetime import datetime, timezone
import uuid

logger = logging.getLogger(__name__)


class DeviceService:
    @staticmethod
    def _normalize_device_id(device_id: str) -> str:
        """Chuẩn hóa device_id và đảm bảo không bao giờ trả về None"""
        if device_id is None:
            logger.error("device_id is None in _normalize_device_id")
            return f"error_fallback_{uuid.uuid4().hex}"

        if not isinstance(device_id, str):
            logger.warning(
                f"device_id is not string: {type(device_id)}, converting to string"
            )
            device_id = str(device_id)

        return device_id.strip().lower()

    @staticmethod
    def add_verified_device(
        db: Session, user_id: int, device_id: str, device_info: Optional[Dict] = None
    ) -> bool:
        """Thêm device vào danh sách verified devices với thông tin device"""
        try:
            logger.debug(
                f"Adding verified device: user_id={user_id}, device_id={device_id}, device_info={device_info}"
            )

            # FIX: Kiểm tra device_id không được None
            if device_id is None:
                logger.error("device_id is None, cannot add device")
                return False

            user = db.query(User).filter(User.id == user_id).first()
            if not user:
                logger.error(f"User {user_id} not found")
                return False

            # Chuẩn hóa device_id
            normalized_device_id = DeviceService._normalize_device_id(device_id)
            logger.debug(f"Normalized device_id: {normalized_device_id}")

            # Khởi tạo nếu chưa có
            if user.verified_devices is None:
                user.verified_devices = []
                logger.debug(f"Initialized verified_devices for user {user_id}")

            # DEBUG: Log current verified_devices
            logger.debug(
                f"Current verified_devices for user {user_id}: {user.verified_devices}"
            )

            # Check if device exists and update or add
            existing_entry = None
            if user.verified_devices:
                for idx, d in enumerate(user.verified_devices):
                    d_id = None
                    if isinstance(d, dict):
                        d_id = d.get("device_id")
                    else:
                        d_id = d

                    if DeviceService._normalize_device_id(d_id) == normalized_device_id:
                        # Device exists, update it
                        current_time = datetime.now(timezone.utc).isoformat()
                        logger.info(
                            f"Updating verified_at for existing device {normalized_device_id}"
                        )

                        if isinstance(d, dict):
                            # It's a dict, update verified_at
                            d["verified_at"] = current_time
                            if device_info:
                                d.update(device_info)
                        else:
                            # It's a string, convert to dict
                            user.verified_devices[idx] = {
                                "device_id": normalized_device_id,
                                "verified_at": current_time,
                                **(device_info or {}),
                            }

                        # SQLAlchemy might not detect mutation of JSON list elements automatically
                        # flag modified to be sure
                        from sqlalchemy.orm.attributes import flag_modified

                        flag_modified(user, "verified_devices")

                        db.commit()
                        return True

            # If not found, append new

            # Tạo device entry với thông tin chi tiết
            current_time = datetime.now(timezone.utc).isoformat()

            device_entry = {
                "device_id": normalized_device_id,
                "verified_at": current_time,
                **(device_info or {}),  # Đảm bảo device_info không phải None
            }

            logger.info(f"Adding device entry: {device_entry}")
            user.verified_devices.append(device_entry)

            # CRITICAL FIX: SQLAlchemy needs flag_modified for list append on JSON column
            from sqlalchemy.orm.attributes import flag_modified

            flag_modified(user, "verified_devices")

            db.commit()
            db.refresh(user)

            logger.info(
                f"Added device {normalized_device_id} to verified devices for user {user_id}"
            )
            return True

        except Exception as e:
            logger.error(f"Error adding verified device: {str(e)}")
            logger.error(f"Full error details:", exc_info=True)
            db.rollback()
            return False

    @staticmethod
    def is_device_verified(db: Session, user_id: int, device_id: str) -> bool:
        """Kiểm tra device đã được verify chưa và còn hạn không (7 ngày)"""
        try:
            user = db.query(User).filter(User.id == user_id).first()
            if not user or not user.verified_devices:
                logger.debug(
                    f"User {user_id} has no verified devices (or user not found)"
                )
                return False

            normalized_device_id = DeviceService._normalize_device_id(device_id)
            logger.debug(f"Checking verification for device: {normalized_device_id}")
            logger.debug(f"Current stored devices: {user.verified_devices}")

            for device in user.verified_devices:
                # Handle dictionary format
                if isinstance(device, dict):
                    if (
                        DeviceService._normalize_device_id(device.get("device_id"))
                        == normalized_device_id
                    ):
                        # Check expiration if verified_at exists
                        verified_at_str = device.get("verified_at")
                        if verified_at_str:
                            try:
                                # Handle timezone awareness safely
                                try:
                                    verified_at = datetime.fromisoformat(
                                        verified_at_str
                                    )
                                except Exception:
                                    # Try parsing manually if isoformat fails (rare)
                                    verified_at = None

                                if verified_at:
                                    # Ensure verified_at is timezone-aware
                                    if verified_at.tzinfo is None:
                                        verified_at = verified_at.replace(
                                            tzinfo=timezone.utc
                                        )

                                    now = datetime.now(timezone.utc)

                                    # DEBUG LOG
                                    logger.debug(
                                        f"Checking expiry: Now={now}, VerifiedAt={verified_at}, Diff={(now - verified_at).days} days"
                                    )

                                    if (now - verified_at).days >= 7:
                                        logger.info(
                                            f"Device {normalized_device_id} verification expired (> 7 days)"
                                        )
                                        return False
                                else:
                                    logger.warning(
                                        f"Could not parse verified_at: {verified_at_str}"
                                    )
                                    # Treat as undefined? Or valid?
                                    # Let's verify again to be safe/fix data
                                    return False

                            except Exception as e:
                                logger.warning(
                                    f"Error checking expiration for device {normalized_device_id}: {str(e)}"
                                )
                                return False
                        return True

                # Handle legacy string format (assume trusted indefinitely or migrate?)
                # Requirement says "after 7 days must verify again".
                # Legacy strings don't have timestamp.
                # Either we treat them as "old = expired" or "old = permanent".
                # Let's treat them as valid for now to avoid breaking existing users immediately
                # unless we want to force re-verify.
                elif isinstance(device, str):
                    if (
                        DeviceService._normalize_device_id(device)
                        == normalized_device_id
                    ):
                        return True

            return False

        except Exception as e:
            logger.error(f"Error checking device verification: {str(e)}")
            return False

    @staticmethod
    def get_verified_devices(db: Session, user_id: int) -> List[Dict]:
        """Lấy danh sách verified devices với thông tin đầy đủ"""
        try:
            user = db.query(User).filter(User.id == user_id).first()
            if not user or not user.verified_devices:
                return []

            # Chuẩn hóa định dạng trả về
            devices = []
            for device in user.verified_devices:
                if isinstance(device, dict):
                    devices.append(device)
                else:
                    devices.append(
                        {
                            "device_id": device,
                            "verified_at": None,
                            "browser": "Unknown",
                            "os": "Unknown",
                            "type": "Unknown",
                        }
                    )

            return devices

        except Exception as e:
            logger.error(f"Error getting verified devices: {str(e)}")
            return []

    @staticmethod
    def remove_verified_device(db: Session, user_id: int, device_id: str) -> bool:
        """Xóa device khỏi danh sách verified"""
        try:
            user = db.query(User).filter(User.id == user_id).first()
            if not user or not user.verified_devices:
                return False

            normalized_device_id = DeviceService._normalize_device_id(device_id)
            original_count = len(user.verified_devices)

            # Lọc bỏ device
            user.verified_devices = [
                d
                for d in user.verified_devices
                if (
                    isinstance(d, dict)
                    and DeviceService._normalize_device_id(d.get("device_id"))
                    != normalized_device_id
                )
                or (
                    not isinstance(d, dict)
                    and DeviceService._normalize_device_id(d) != normalized_device_id
                )
            ]

            if len(user.verified_devices) < original_count:
                db.commit()
                db.refresh(user)
                logger.info(f"Removed device {device_id} from user {user_id}")
                return True
            return False

        except Exception as e:
            logger.error(f"Error removing verified device: {str(e)}")
            db.rollback()
            return False
