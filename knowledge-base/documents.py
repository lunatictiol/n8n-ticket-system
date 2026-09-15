"""Structured knowledge-base content — single source of truth.

Both `generate_pdfs.py` (renders these to PDF) and `ingestion/seed_qdrant.py`
(embeds and upserts to Qdrant) import DOCUMENTS from here, so the vectors in
Qdrant always match the PDFs exactly.

M2 ships three documents to exercise the grounding gate: two customer_safe, one
internal_only (the negative-retrieval test). M3 replaces this with ten full
documents generated with real structure. One consistent fictional company
identity across all of them — contradictions poison retrieval.

Company identity (keep consistent everywhere):
  Company:        Northwind Cloud
  Product:        Northwind Drive
  Support email:  support@northwind.example
  SLA tiers:      Standard 24h, Priority 8h, Critical 2h (business hours)
"""

COMPANY = "Northwind Cloud"
PRODUCT = "Northwind Drive"
SUPPORT_EMAIL = "support@northwind.example"

DOCUMENTS = [
    {
        "doc_id": "refund-policy",
        "name": "Refund Policy",
        "doc_type": "policy",
        "access_level": "customer_safe",
        "version": "1.0",
        "effective_date": "2026-01-01",
        "sections": [
            {
                "heading": "1. Eligibility",
                "body": (
                    f"Customers may request a full refund of any {PRODUCT} subscription "
                    "within 30 calendar days of the original purchase or renewal date. "
                    "The 30-day window is measured from the date the charge appears on the "
                    "customer's statement. Refunds outside this window are not granted except "
                    "where required by law."
                ),
            },
            {
                "heading": "2. How to request a refund",
                "body": (
                    f"To request a refund, the customer emails {SUPPORT_EMAIL} with the "
                    "account email address and the invoice number. No reason is required for "
                    "requests inside the 30-day window. The support team acknowledges every "
                    "refund request within one business day."
                ),
            },
            {
                "heading": "3. Processing time",
                "body": (
                    "Approved refunds are issued to the original payment method within 5 to 10 "
                    "business days. The customer receives an email confirmation with the refund "
                    "reference once the refund is submitted to the payment processor."
                ),
            },
            {
                "heading": "4. Non-refundable items",
                "body": (
                    "One-time data-migration services and add-on storage packs already consumed "
                    "are non-refundable. Monthly subscriptions cancelled mid-cycle are refunded "
                    "on a pro-rata basis only within the 30-day eligibility window."
                ),
            },
        ],
    },
    {
        "doc_id": "product-documentation",
        "name": "Product Documentation",
        "doc_type": "documentation",
        "access_level": "customer_safe",
        "version": "1.0",
        "effective_date": "2026-01-01",
        "sections": [
            {
                "heading": "1. Storage tiers",
                "body": (
                    f"{PRODUCT} offers three storage tiers. Free includes 5 GB. Personal includes "
                    "500 GB for a single user. Business includes 2 TB per user with shared team "
                    "folders. Storage limits are enforced at upload time; uploads that would "
                    "exceed the tier limit are rejected with an error message."
                ),
            },
            {
                "heading": "2. File sync and versioning",
                "body": (
                    f"{PRODUCT} keeps the last 30 versions of every file on Personal and Business "
                    "tiers, and the last 3 versions on Free. Deleted files are retained in the "
                    "Trash for 30 days before permanent removal. Version history is accessible "
                    "from the file's context menu in the web app."
                ),
            },
            {
                "heading": "3. Sharing and links",
                "body": (
                    "Files and folders can be shared by email invitation or by generating a "
                    "shareable link. Link permissions are view-only or edit. Business-tier links "
                    "can be password-protected and set to expire after a chosen number of days."
                ),
            },
            {
                "heading": "4. Supported platforms",
                "body": (
                    f"{PRODUCT} provides a web app, desktop clients for Windows and macOS, and "
                    "mobile apps for iOS and Android. Files uploaded on any platform sync to all "
                    "others automatically when the device is online."
                ),
            },
        ],
    },
    {
        "doc_id": "support-handbook",
        "name": "Support Handbook",
        "doc_type": "handbook",
        "access_level": "internal_only",
        "version": "1.0",
        "effective_date": "2026-01-01",
        "sections": [
            {
                "heading": "1. Internal escalation tiers",
                "body": (
                    "Tier 1 agents handle general enquiries. Tier 2 handles billing disputes and "
                    "sync failures. Tier 3 (engineering on-call) handles data-integrity and "
                    "security incidents. Agents must never share internal escalation contacts, "
                    "on-call phone numbers, or this handbook with customers."
                ),
            },
            {
                "heading": "2. Agent discount authority",
                "body": (
                    "Tier 1 agents may offer up to a 10 percent goodwill credit without approval. "
                    "Credits above 10 percent require Tier 2 supervisor sign-off. This authority "
                    "is internal and must never be disclosed to customers or used as leverage in "
                    "a conversation."
                ),
            },
            {
                "heading": "3. Handling abusive contacts",
                "body": (
                    "Agents may issue one warning and then end a session that becomes abusive. "
                    "Repeat offenders are flagged internally for account review. The internal "
                    "flagging process is confidential."
                ),
            },
        ],
    },
]
