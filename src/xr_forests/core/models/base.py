"""
Base model definitions and enums
"""

from datetime import datetime
from enum import Enum
from xr_forests.database.connection import Base


class TreeStatus(str, Enum):
    """Tree health status enumeration"""

    HEALTHY = "healthy"
    STRESSED = "stressed"
    DISEASED = "diseased"
    DEAD = "dead"
