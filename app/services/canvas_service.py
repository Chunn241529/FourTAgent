import logging
from typing import List, Optional
from sqlalchemy.orm import Session
from app.models import Canvas
from app.db import SessionLocal

logger = logging.getLogger(__name__)


class CanvasService:
    def __init__(self):
        pass

    def create_canvas(
        self,
        user_id: int,
        title: str,
        content: str,
        type: str = "markdown",
        db: Session = None,
    ) -> Optional[Canvas]:
        """
        Create a new canvas item.
        """
        should_close = False
        if not db:
            db = SessionLocal()
            should_close = True

        try:
            new_canvas = Canvas(
                user_id=user_id, title=title, content=content, type=type
            )
            db.add(new_canvas)
            db.commit()
            db.refresh(new_canvas)
            return new_canvas
        except Exception as e:
            logger.error(f"Error creating canvas: {e}")
            return None
        finally:
            if should_close:
                db.close()

    def get_canvas(
        self, canvas_id: int, user_id: int, db: Session = None
    ) -> Optional[Canvas]:
        """
        Get a canvas item by ID.
        """
        should_close = False
        if not db:
            db = SessionLocal()
            should_close = True

        try:
            return (
                db.query(Canvas)
                .filter(Canvas.id == canvas_id, Canvas.user_id == user_id)
                .first()
            )
        except Exception as e:
            logger.error(f"Error getting canvas {canvas_id}: {e}")
            return None
        finally:
            if should_close:
                db.close()

    def list_canvases(self, user_id: int, db: Session = None) -> List[Canvas]:
        """
        List all canvas items for a user.
        """
        should_close = False
        if not db:
            db = SessionLocal()
            should_close = True

        try:
            return (
                db.query(Canvas)
                .filter(Canvas.user_id == user_id)
                .order_by(Canvas.updated_at.desc())
                .all()
            )
        except Exception as e:
            logger.error(f"Error listing canvases: {e}")
            return []
        finally:
            if should_close:
                db.close()

    def update_canvas(
        self,
        canvas_id: int,
        user_id: int,
        content: Optional[str] = None,
        title: Optional[str] = None,
        db: Session = None,
    ) -> Optional[Canvas]:
        """
        Update a canvas item.
        """
        should_close = False
        if not db:
            db = SessionLocal()
            should_close = True

        try:
            canvas = (
                db.query(Canvas)
                .filter(Canvas.id == canvas_id, Canvas.user_id == user_id)
                .first()
            )
            if not canvas:
                return None

            if content is not None:
                canvas.content = content
            if title is not None:
                canvas.title = title

            db.commit()
            db.refresh(canvas)
            return canvas
        except Exception as e:
            logger.error(f"Error updating canvas {canvas_id}: {e}")
            return None
        finally:
            if should_close:
                db.close()

    def delete_canvas(self, canvas_id: int, user_id: int, db: Session = None) -> bool:
        """
        Delete a canvas item.
        """
        should_close = False
        if not db:
            db = SessionLocal()
            should_close = True

        try:
            canvas = (
                db.query(Canvas)
                .filter(Canvas.id == canvas_id, Canvas.user_id == user_id)
                .first()
            )
            if not canvas:
                return False

            db.delete(canvas)
            db.commit()
            return True
        except Exception as e:
            logger.error(f"Error deleting canvas {canvas_id}: {e}")
            return False
        finally:
            if should_close:
                db.close()

    def get_latest_canvas(self, user_id: int, db: Session = None) -> Optional[Canvas]:
        """
        Get the most recently updated canvas for a user.
        """
        should_close = False
        if not db:
            db = SessionLocal()
            should_close = True

        try:
            return (
                db.query(Canvas)
                .filter(Canvas.user_id == user_id)
                .order_by(Canvas.updated_at.desc())
                .first()
            )
        except Exception as e:
            logger.error(f"Error getting latest canvas: {e}")
            return None
        finally:
            if should_close:
                db.close()


canvas_service = CanvasService()
