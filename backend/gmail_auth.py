"""One-time Gmail sign-in (read-only). Opens a browser; saves gmail_token.json.

Needs google_client.json next to this file: Google Cloud Console -> APIs & Services
-> Credentials -> OAuth client ID (type "Desktop app") -> Download JSON.
Then push the token to the server with ./deploy.sh --env.
"""
import os
from pathlib import Path

from google_auth_oauthlib.flow import InstalledAppFlow

from main import GMAIL_SCOPES, GMAIL_TOKEN

flow = InstalledAppFlow.from_client_secrets_file(Path(__file__).with_name("google_client.json"), GMAIL_SCOPES)
creds = flow.run_local_server(port=0)
GMAIL_TOKEN.write_text(creds.to_json())
os.chmod(GMAIL_TOKEN, 0o600)
print(f"Gmail connected (read-only). Token saved to {GMAIL_TOKEN.name}")
