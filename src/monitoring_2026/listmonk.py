import os

import requests

BASE_URL = (
    "https://listmonk-demo-afhcg8e2hde0fxca.eastus2-01.azurewebsites.net/api"  # noqa
)

BASE_CAMPAIGN_ID = 8
BASE_TRANSACTIONAL_ID = 12

USERNAME = os.getenv("DSCI_LISTMONK_API_USERNAME")
PASSWORD = os.getenv("DSCI_LISTMONK_API_KEY")


def create_campaign(
    name: str = "test_campaign",
    subject: str = "Test Subject",
    list_ids: list[int] = None,
    template_id: int = BASE_CAMPAIGN_ID,
    body: str = "TEST CONTENT",
):
    if list_ids is None:
        list_ids = []
    create_payload = {
        "name": name,
        "subject": subject,
        "lists": list_ids,
        "template_id": template_id,
        "type": "regular",
        "content_type": "html",
        "body": body,
    }

    r = requests.post(
        f"{BASE_URL}/campaigns",
        auth=(USERNAME, PASSWORD),
        json=create_payload,
    )

    r.raise_for_status()
    campaign = r.json()["data"]
    campaign_id = campaign["id"]
    return campaign_id


def send_campaign(campaign_id: int):
    r = requests.put(
        f"{BASE_URL}/campaigns/{campaign_id}/status",
        auth=(USERNAME, PASSWORD),
        json={"status": "running"},
    )
    r.raise_for_status()


def send_transactional(
    to_emails: list[tuple[str, str]],
    subject: str,
    template_id: int = BASE_TRANSACTIONAL_ID,
    cc_emails: list[tuple[str, str]] = None,
    data: dict = None,
):
    payload = {
        "subscriber_email": to_emails[0][1],
        "template_id": template_id,
        "from_email": "OCHA Data Science <ocha-datascience@un.org>",
        "content_type": "html",
        "subject": subject,
        "data": data or {},
        "headers": [
            {
                "To": ", ".join(
                    [f"{name} <{email}>" for name, email in to_emails]
                )
            },
            {
                "Cc": ", ".join(
                    [f"{name} <{email}>" for name, email in cc_emails or []]
                )
            },
        ],
    }

    r = requests.post(
        f"{BASE_URL}/tx",
        auth=(USERNAME, PASSWORD),
        json=payload,
    )
    if not r.ok:
        print("Status:", r.status_code)
        print("Response text:", r.text)
        print("Payload sent:", payload)

    r.raise_for_status()
    return r.json()
