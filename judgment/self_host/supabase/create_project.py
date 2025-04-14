import os
import time
import json
import requests
from dotenv import load_dotenv

load_dotenv()

SUPABASE_TOKEN = os.getenv("SUPABASE_ACCESS_TOKEN")
ORG_ID = os.getenv("SUPABASE_ORG_ID")
DB_PASSWORD = os.getenv("SUPABASE_DB_PASSWORD")

def get_existing_project(org_id: str, project_name: str) -> dict:
    """Check if a project with the given name already exists in the organization."""
    print(f"Checking for existing project '{project_name}'...")
    url = f"https://api.supabase.com/v1/projects"
    res = requests.get(url, headers=HEADERS)
    res.raise_for_status()
    all_projects = res.json()
    for project in all_projects:
        if project["name"] == project_name and project["organization_id"] == org_id:
            print(f"Found existing project with ID: {project['id']}")
            return project
    print("No existing project found...")
    return None

def create_project(org_id: str, project_name: str, db_password: str, supabase_compute_size: str) -> dict:
    print("Creating Supabase project...")
    request_json = {
        "name": project_name,
        "organization_id": org_id,
        "db_pass": db_password,
        "region": "us-west-1",
    }
    if supabase_compute_size != "nano":
        request_json["desired_instance_size"] = supabase_compute_size
    res = requests.post(
        "https://api.supabase.com/v1/projects",
        headers=HEADERS,
        json=request_json
    )

    res.raise_for_status()
    data = res.json()
    print("Project created. Waiting for provisioning...")
    return data


def wait_for_project_ready(project_ref: str, timeout: int = 180) -> bool:
    url = f"https://api.supabase.com/v1/projects/{project_ref}"
    for _ in range(timeout // 10):
        res = requests.get(url, headers=HEADERS)
        if res.status_code == 200 and res.json().get("status") == "ACTIVE_HEALTHY":
            return True
        time.sleep(10)
    raise TimeoutError("Supabase project did not become ACTIVE in time.")


def get_api_keys(project_ref: str) -> tuple[str, str]:
    print("Fetching API keys...")
    url = f"https://api.supabase.com/v1/projects/{project_ref}/api-keys"
    res = requests.get(url, headers=HEADERS)
    res.raise_for_status()
    keys = res.json()
    anon = next(k["api_key"] for k in keys if k["name"] == "anon")
    service_role = next(k["api_key"] for k in keys if k["name"] == "service_role")
    return anon, service_role

def get_project_jwt_secret(project_ref: str) -> str:
    url = f"https://api.supabase.com/v1/projects/{project_ref}/postgrest"
    res = requests.get(url, headers=HEADERS)
    res.raise_for_status()
    return res.json().get("jwt_secret")

def create_project_and_get_secrets(supabase_token: str = SUPABASE_TOKEN, org_id: str = ORG_ID, project_name: str = "Judgment Database", db_password: str = DB_PASSWORD, supabase_compute_size: str = "small"):
    global HEADERS
    HEADERS = {
        "Authorization": f"Bearer {supabase_token}",
        "Content-Type": "application/json"
    }

    # Check for existing project
    existing_project = get_existing_project(org_id, project_name)
    if existing_project:
        raise ValueError(f"A project named '{project_name}' already exists in this organization. Please choose a different name or delete the existing project.")

    # Create new project
    project = create_project(org_id, project_name, db_password, supabase_compute_size)
    project_ref = project["id"]
    project_id = project["id"]
    url = f"https://{project_ref}.supabase.co"
    wait_for_project_ready(project_ref)

    anon_key, service_role_key = get_api_keys(project_ref)
    jwt_secret = get_project_jwt_secret(project_ref)

    output = {
        "supabase_url": url,
        "supabase_anon_key": anon_key,
        "supabase_service_role_key": service_role_key,
        "supabase_jwt_secret": jwt_secret,
        "supabase_project_id": project_id
    }
    
    return output

def main():
    create_project_and_get_secrets()
    
if __name__ == "__main__":
    main()
