from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime

from app.db import get_db
from app.services.canvas_service import canvas_service
from app.utils import verify_jwt
from app.models import User

router = APIRouter(
    prefix="/canvas",
    tags=["canvas"],
    responses={404: {"description": "Not found"}},
)


class CanvasBase(BaseModel):
    title: str
    content: str
    type: str = "markdown"


class CanvasCreate(CanvasBase):
    pass


class CanvasUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    type: Optional[str] = None


class CanvasResponse(CanvasBase):
    id: int
    user_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        orm_mode = True


@router.get("/", response_model=List[CanvasResponse])
async def list_canvases(
    user_id: int = Depends(verify_jwt),
):
    """List all canvases for the current user."""
    return canvas_service.list_canvases(user_id)


@router.post("/", response_model=CanvasResponse)
async def create_canvas(
    canvas: CanvasCreate,
    user_id: int = Depends(verify_jwt),
):
    """Create a new canvas."""
    result = canvas_service.create_canvas(
        user_id=user_id,
        title=canvas.title,
        content=canvas.content,
        type=canvas.type,
    )
    if not result:
        raise HTTPException(status_code=500, detail="Failed to create canvas")
    return result


@router.get("/{canvas_id}", response_model=CanvasResponse)
async def read_canvas(
    canvas_id: int,
    user_id: int = Depends(verify_jwt),
):
    """Get a specific canvas."""
    result = canvas_service.get_canvas(canvas_id, user_id)
    if not result:
        raise HTTPException(status_code=404, detail="Canvas not found")
    return result


@router.put("/{canvas_id}", response_model=CanvasResponse)
async def update_canvas(
    canvas_id: int,
    canvas: CanvasUpdate,
    user_id: int = Depends(verify_jwt),
):
    """Update a canvas."""
    result = canvas_service.update_canvas(
        canvas_id=canvas_id,
        user_id=user_id,
        content=canvas.content,
        title=canvas.title,
    )
    if not result:
        raise HTTPException(status_code=404, detail="Canvas not found or update failed")
    return result


@router.delete("/{canvas_id}")
async def delete_canvas(
    canvas_id: int,
    user_id: int = Depends(verify_jwt),
):
    """Delete a canvas."""
    if canvas_service.delete_canvas(canvas_id, user_id):
        return {"message": "Canvas deleted"}
    raise HTTPException(status_code=404, detail="Canvas not found")
