from dataclasses import dataclass


@dataclass
class Session:
    role: str
    operator_name: str

    @property
    def actor_label(self) -> str:
        return f"{self.role} ({self.operator_name})"
