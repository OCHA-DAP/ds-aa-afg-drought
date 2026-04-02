"""
Listmonk transactional and campaign email helpers.

Listmonk API: https://listmonk.app/docs/apis/transactional/

Delivery mechanics (from listmonk source, internal/messenger/email/email.go):
    Listmonk's /api/tx endpoint handles To, Cc, and Bcc headers differently:

    - To header:  COSMETIC ONLY. Sets the display header in the recipient's
      email client but does NOT add addresses to the SMTP envelope. To
      actually deliver to "To" recipients, they must be listed in
      subscriber_emails (with subscriber_mode="external").

    - Cc header:  DELIVERY + DISPLAY. Listmonk parses the Cc header, adds
      addresses to the SMTP envelope (em.Cc), and then removes the header
      (smtppool re-adds it). Recipients see Cc in their client AND receive
      the email.

    - Bcc header: DELIVERY ONLY. Same as Cc — parsed into SMTP envelope
      (em.Bcc) and removed from headers. Recipients receive the email but
      are not visible to other recipients.

    Therefore, send_transactional() uses subscriber_emails for To recipients
    and relies on header parsing for Cc/Bcc delivery.
"""

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
    bcc_emails: list[tuple[str, str]] = None,
    data: dict = None,
):
    """Send a transactional email via Listmonk to multiple recipients.

    Parameters
    ----------
    to_emails : list of (name, email)
        Primary recipients. Delivered via subscriber_emails (envelope).
        Displayed in the To header.
    cc_emails : list of (name, email), optional
        CC recipients. Delivered via Cc header (parsed into envelope by
        Listmonk). Visible to all recipients.
    bcc_emails : list of (name, email), optional
        BCC recipients. Delivered via Bcc header (parsed into envelope by
        Listmonk). Hidden from other recipients.
    """
    to_addresses = [email for _, email in to_emails]

    payload = {
        "subscriber_emails": to_addresses,
        "subscriber_mode": "external",
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
            {
                "Bcc": ", ".join(
                    [f"{name} <{email}>" for name, email in bcc_emails or []]
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
