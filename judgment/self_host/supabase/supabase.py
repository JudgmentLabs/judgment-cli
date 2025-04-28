import os
import time
import json
import requests
import psycopg2
import typer
from dotenv import load_dotenv
from typing import Optional, Tuple, Dict, Callable
from contextlib import contextmanager
from supabase import create_client, Client

load_dotenv()

class SupabaseClient:
    def __init__(self, supabase_token: str, org_id: str, db_password: str):
        self.supabase_token = supabase_token
        self.org_id = org_id
        self.db_password = db_password
        self.headers = {
            "Authorization": f"Bearer {supabase_token}",
            "Content-Type": "application/json"
        }

    @contextmanager
    def _get_db_connection(self, db_url: str):
        """Helper method to manage database connections and cursors."""
        conn = psycopg2.connect(f"postgres://postgres:{self.db_password}@db.{db_url.replace('https://', '')}:5432/postgres")
        cursor = conn.cursor()
        try:
            yield cursor
            conn.commit()
        finally:
            cursor.close()
            conn.close()

    def get_existing_project(self, project_name: str) -> Optional[Dict]:
        """Check if a project with the given name already exists in the organization."""
        print(f"Checking for existing project '{project_name}'...")
        url = "https://api.supabase.com/v1/projects"
        res = requests.get(url, headers=self.headers)
        res.raise_for_status()
        all_projects = res.json()
        for project in all_projects:
            if project["name"] == project_name and project["organization_id"] == self.org_id:
                print(f"Found existing project with ID: {project['id']}")
                return project
        print("No existing project found...")
        return None

    def create_project(self, project_name: str, supabase_compute_size: str) -> Dict:
        print("Creating Supabase project...")
        request_json = {
            "name": project_name,
            "organization_id": self.org_id,
            "db_pass": self.db_password,
            "region": "us-west-1",
        }
        if supabase_compute_size != "nano":
            request_json["desired_instance_size"] = supabase_compute_size
        res = requests.post(
            "https://api.supabase.com/v1/projects",
            headers=self.headers,
            json=request_json
        )
        res.raise_for_status()
        data = res.json()
        print("Project created. Waiting for provisioning...")
        return data

    def wait_for_project_ready(self, project_ref: str, timeout: int = 180) -> bool:
        url = f"https://api.supabase.com/v1/projects/{project_ref}"
        for _ in range(timeout // 10):
            res = requests.get(url, headers=self.headers)
            if res.status_code == 200 and res.json().get("status") == "ACTIVE_HEALTHY":
                return True
            time.sleep(10)
        raise TimeoutError("Supabase project did not become ACTIVE in time.")

    def get_api_keys(self, project_ref: str) -> Tuple[str, str]:
        print("Fetching API keys...")
        url = f"https://api.supabase.com/v1/projects/{project_ref}/api-keys"
        res = requests.get(url, headers=self.headers)
        res.raise_for_status()
        keys = res.json()
        anon = next(k["api_key"] for k in keys if k["name"] == "anon")
        service_role = next(k["api_key"] for k in keys if k["name"] == "service_role")
        return anon, service_role

    def get_project_jwt_secret(self, project_ref: str) -> str:
        print("Fetching JWT secret...")
        url = f"https://api.supabase.com/v1/projects/{project_ref}/postgrest"
        res = requests.get(url, headers=self.headers)
        res.raise_for_status()
        return res.json().get("jwt_secret")

    def load_schema(self, db_url: str):
        print("Loading schema...")
        with open(os.path.abspath(os.path.join(os.path.dirname(__file__), 'schema.sql')), 'r') as file:
            schema_sql = file.read()
        with self._get_db_connection(db_url) as cursor:
            cursor.execute(schema_sql)

    def create_root_user(self, supabase_url: str, supabase_service_role_key: str, email: str, password: str):
        """Create a root user using Supabase Auth API."""
        print("Creating root user...")
        supabase: Client = create_client(supabase_url, supabase_service_role_key)
        
        # Create the user
        try:
            response = supabase.auth.admin.create_user({
                "email": email,
                "password": password,
                "email_confirm": True,  # Auto-confirm the email
                "user_metadata": {
                    "role": "root"
                }
            })
        except Exception as e:
            raise Exception(f"Failed to create root user: {e}")
        
        print("Root user created successfully!")

    def create_project_and_get_secrets(self, project_name: str = "Judgment Database", supabase_compute_size: str = "small") -> Dict:
        # Check for existing project
        existing_project = self.get_existing_project(project_name)
        if existing_project:
            
            if not typer.confirm(f"A project named '{project_name}' already exists in this organization. Has this project been configured for Judgment, and if so, would you like to use it for your self-hosted Judgment instance?"):
                print("Please choose a different name or delete the existing project.")
                raise typer.Exit(0)
            
        # Create new project
        if not existing_project:
            project = self.create_project(project_name, supabase_compute_size)
            project_ref = project["id"]
            project_id = project["id"]
        else:
            project_ref = existing_project["id"]
            project_id = existing_project["id"]

        url = f"https://{project_ref}.supabase.co"
        self.wait_for_project_ready(project_ref)

        anon_key, service_role_key = self.get_api_keys(project_ref)
        jwt_secret = self.get_project_jwt_secret(project_ref)

        if not existing_project:
            # Update auth configuration
            print("Updating auth configuration...")
            auth_config_url = f"https://api.supabase.com/v1/projects/{project_ref}/config/auth"
            auth_config_data = {
                "mailer_autoconfirm": True,
                "mailer_secure_email_change_enabled": False
            }
            res = requests.patch(auth_config_url, headers=self.headers, json=auth_config_data)
            res.raise_for_status()
            print("Auth configuration updated successfully!")
            
            # Load Judgment schema onto the database
            self.load_schema(url)
            print("Supabase project created and schema loaded successfully!")
        else:
            print("Retrieved existing project secrets...")

        return {
            "supabase_url": url,
            "supabase_anon_key": anon_key,
            "supabase_service_role_key": service_role_key,
            "supabase_jwt_secret": jwt_secret,
            "supabase_project_id": project_id
        }, existing_project is not None
