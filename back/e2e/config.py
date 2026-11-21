import os
from dataclasses import dataclass, field


@dataclass(frozen=True)
class E2EConfig:
    api_base_url: str
    supabase_url: str
    supabase_key: str
    email: str = field(repr=False)
    password: str = field(repr=False)
    second_email: str = field(default="", repr=False)
    second_password: str = field(default="", repr=False)
    service_role_key: str = field(default="", repr=False)
    image_path: str = ""

    @classmethod
    def from_env(cls):
        return cls(
            api_base_url=os.environ.get("E2E_API_BASE_URL", "").rstrip("/"),
            supabase_url=os.environ.get("E2E_SUPABASE_URL", "").rstrip("/"),
            supabase_key=os.environ.get("E2E_SUPABASE_PUBLISHABLE_KEY", ""),
            email=os.environ.get("E2E_EMAIL", ""),
            password=os.environ.get("E2E_PASSWORD", ""),
            second_email=os.environ.get("E2E_SECOND_EMAIL", ""),
            second_password=os.environ.get("E2E_SECOND_PASSWORD", ""),
            service_role_key=os.environ.get("E2E_SERVICE_ROLE_KEY", ""),
            image_path=os.environ.get("E2E_IMAGE_PATH", ""),
        )

    def missing(self):
        values = {
            "E2E_API_BASE_URL": self.api_base_url,
            "E2E_SUPABASE_URL": self.supabase_url,
            "E2E_SUPABASE_PUBLISHABLE_KEY": self.supabase_key,
            "E2E_EMAIL": self.email,
            "E2E_PASSWORD": self.password,
        }
        return [name for name, value in values.items() if not value]
