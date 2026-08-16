# WEMOTE

Git-backed Cloudflare Pages front end for the local WEMOTE bridge.

Current web version: **0.4.2**

## Cloudflare Pages

Connect this repository to Cloudflare Pages using the `main` branch.

This is a plain static site:

- Framework preset: None
- Build command: leave blank
- Build output directory: `/`

The web app stores the current `trycloudflare.com` bridge URL in the browser and sends commands to the local WEMOTE bridge through that tunnel.

The Windows bridge remains the source of truth for schedules, Wemo discovery, device state, and settings.
