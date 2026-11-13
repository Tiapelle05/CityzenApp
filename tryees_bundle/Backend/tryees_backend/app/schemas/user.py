from pydantic import BaseModel
from app.db.models import TypeUser

class UserBase(BaseModel):
    username: str
    type: TypeUser

class UserCreate(UserBase):
    password: str

class UserUpdate(BaseModel):
    username: str | None = None
    type: TypeUser | None = None
    password: str | None = None

class UserInDBBase(UserBase):
    id: int

    model_config = {"from_attributes": True}

class User(UserInDBBase):
    pass
