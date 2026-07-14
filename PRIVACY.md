# Privacy

BIFROST Browser does not include telemetry, analytics, crash reporting, advertising identifiers, accounts, cloud sync, or a JourdanLabs browsing proxy.

## Data that stays on the device

- WebKit browsing data such as cookies and site storage
- bookmarks and the user blocklist
- the LUNA navigation ledger
- user-requested ledger exports

The LUNA ledger contains navigation metadata and verdict evidence. It is hash-chained for tamper evidence, but it is not encrypted. Anyone with access to the user account or an exported ledger may be able to read it.

## Network behavior

Web pages connect directly through WebKit. BIFROST does not send page contents or answer text to JourdanLabs. The AI-answer observer reads supported page content locally and sends it only from the main frame into the native process for deterministic evaluation.

## Deletion

Bookmarks, blocklist entries, and exports can be removed from their local application-support paths. Removing the app container deletes sandboxed local state. Ledger rows are append-only inside the product; delete the ledger file only when you intentionally want to discard the entire local audit history.
